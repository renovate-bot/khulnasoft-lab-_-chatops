# frozen_string_literal: true

module Chatops
  module Commands
    # Namespace class
    class Namespace
      include Command

      usage "#{command_name} [SUBCOMMAND] [OPTIONS]"
      description 'Managing of namespaces using the GitLab API.'

      # All the available subcommands.
      COMMANDS = Set.new(%w[find minutes])

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Obtaining details about a single namespace:

              namespace find alice

            Setting additional minutes quota for a namespace:

              namespace minutes alice 2000
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command, *arguments[1..-1])
        else
          unsupported_command
        end
      end

      def find(*names)
        return 'You must supply one or more namespace paths or IDs.' if names.empty?
        return 'Too many namespaces provided (max 5).' if names.size > 5

        client = Gitlab::Client.new(token: gitlab_token)

        errors = []
        namespaces_info = names.map do |n|
          namespace_info, err = find_namespace(client, n)

          if err
            errors << err
            next
          end

          namespace_info
        end.compact

        namespaces_info.each do |namespace_info|
          submit_namespace_details(namespace_info)
        end

        errors.join("\n") unless errors.empty?
      end

      def minutes(name = nil, minutes = nil)
        return 'You must supply a namespace path or ID to update.' unless name
        return 'You must specify the total extra minutes.' unless minutes

        client = Gitlab::Client.new(token: gitlab_token)
        namespace = client.set_namespace_extra_minutes(name, minutes)

        return namespace_not_found_error(name) unless namespace

        minutes_updated(name, minutes)
      end

      def submit_namespace_details(namespace) # rubocop:disable Metrics/MethodLength
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
            attachments: [
              {
                fields: [
                  {
                    title: 'ID',
                    value: namespace.id,
                    short: true
                  },
                  {
                    title: 'Name',
                    value: namespace.name,
                    short: true
                  },
                  {
                    title: 'Kind',
                    value: namespace.kind,
                    short: true
                  },
                  {
                    title: 'Path',
                    value: namespace.path,
                    short: true
                  },
                  {
                    title: 'Billable members',
                    value: namespace.billable_members_count,
                    short: true
                  },
                  {
                    title: 'Seats in Use',
                    value: namespace.seats_in_use,
                    short: true
                  },
                  {
                    title: 'Plan',
                    value: namespace.plan,
                    short: true
                  },
                  {
                    title: 'Trial',
                    value: namespace.trial,
                    short: true
                  },
                  {
                    title: 'Trial Ends On',
                    value: namespace.trial_ends_on,
                    short: true
                  },
                  {
                    title: 'Extra Shared Runners Minutes Limit',
                    value: namespace.extra_shared_runners_minutes_limit,
                    short: true
                  }
                ]
              }
            ]
          )
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `namespace --help`.
        HELP
      end

      def find_namespace(client, namespace)
        result = client.find_namespace(namespace)
        [result, nil]
      rescue ::Gitlab::Error::NotFound
        [nil, namespace_not_found_error(namespace)]
      end

      def namespace_not_found_error(name)
        "No namespace could be found for #{name.inspect}."
      end

      def minutes_updated(name, minutes)
        "Extra minutes for #{name.inspect} updated to #{minutes.inspect}."
      end

      def minutes_missing_error
        'You must supply a total amount of minutes to set.'
      end
    end
  end
end
