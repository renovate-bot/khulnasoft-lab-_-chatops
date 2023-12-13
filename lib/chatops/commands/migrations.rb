# frozen_string_literal: true

module Chatops
  module Commands
    class Migrations
      include Command
      include GitlabEnvironments

      DEFAULT_DATABASE = 'main'
      SLACK_MESSAGES = {
        not_found: 'The migration %<version>s does not exist on %<env>s.',
        error: 'Failed to mark the migration %<version>s on %<env>s, the error was: %<message>s.',
        ok: 'Migration %<version>s was marked as successfully executed on %<env>s.'
      }.freeze

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Manipulate migration related tasks.'
      enable_multi_environments

      # All the available subcommands and the corresponding methods to invoke.
      COMMANDS = Set.new(%w[mark])

      VERSION_REGEX = /\A\d{14}\z/

      options do |o|
        o.string(
          '--database',
          "The database to be connected to. If not supplied, connection will be made to '#{DEFAULT_DATABASE}'"
        )

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Mark a database migration as successful.

              migrations mark 20230428500000
              migrations mark 20230428500000 --database ci
        HELP

        GitlabEnvironments.define_environment_options(o)
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments.first

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def mark
        version = arguments[1]

        unless version
          return 'You must specify the version number of the migration. ' \
                 'For example: `migrations mark 20230428500000`'
        end

        unless version.match?(VERSION_REGEX)
          return "The value '#{version}' is invalid. Please use the timestamp of the migration."
        end

        status, api_message = mark_migration(version, database: database)
        message = format(
          SLACK_MESSAGES.fetch(status),
          env: environment.env_name,
          version: version.inspect,
          message: api_message.inspect
        )

        send_migration_details(message)
      end

      private

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The migrations subcommand `#{arguments.first}` is invalid. The following subcommands are available:

          #{list}

          Example:

          ```
          # Marking a migration as successfully executed:
          migrations mark 20230612132239
          migrations mark 20230428500000 --database ci
          ```

          For more information run `migrations --help`.
        MESSAGE
      end

      def mark_migration(version, database:)
        response = gitlab_client.mark_database_migration_by_version(version, database: database)
        return [:not_found, nil] unless response

        [:ok, response.message]
      rescue ::Gitlab::Error::ResponseError => e
        [:error, e.response_message]
      end

      def database
        options[:database] || DEFAULT_DATABASE
      end

      def send_migration_details(message)
        slack_message.send(text: message)
      end

      def gitlab_client
        @gitlab_client ||= Gitlab::Client.new(token: environment.gitlab_token, host: environment.gitlab_host)
      end

      def slack_message
        @slack_message ||= Slack::Message.new(token: slack_token, channel: channel)
      end
    end
  end
end
