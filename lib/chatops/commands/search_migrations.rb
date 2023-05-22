# frozen_string_literal: true

module Chatops
  module Commands
    class SearchMigrations
      include Command
      include GitlabEnvironments

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform search migration related tasks.'
      enable_multi_environments

      # All the available subcommands and the corresponding methods to invoke.
      COMMANDS = Set.new(%w[get list])

      MIGRATION_REGEX = /\A[A-Za-z0-9_]+\z/

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        GitlabEnvironments.define_environment_options(o)
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments.first

        if COMMANDS.include?(command)
          send(command)
        else
          unsupported_command
        end
      end

      private

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The search_migrations subcommand is invalid. The following subcommands are available:

          #{list}

          Some examples:

          ```
          # Listing all migrations:
          search_migrations list

          # To obtain details of a single search_migrations by version or name:
          search_migrations get 20230428500000
          search_migrations get AddSuffixProjectInWikiRid
          ```

          For more information run `search_migrations --help`.
        MESSAGE
      end

      def list
        search_migrations = gitlab_client.search_migrations
        return 'There are no search migrations in the system' if search_migrations.empty?

        search_migrations.each do |m|
          send_search_migration_details(m)
        end

        nil
      end

      def get
        version_or_name = arguments[1]

        unless version_or_name&.match?(MIGRATION_REGEX)
          return 'You must specify the version or name of the search migration. ' \
            'For example: `search_migrations get 20230428500000` or `search_migrations get AddSuffixProjectInWikiRid`'
        end

        migration = get_search_migration(version_or_name)

        return "The migration #{version_or_name.inspect} does not exist on #{environment.env_name}." unless migration

        send_search_migration_details(migration)
      end

      def get_search_migration(version_or_name)
        gitlab_client.find_search_migration_by_version_or_name(version_or_name)
      end

      def send_search_migration_details(search_migration)
        slack_message.send(
          attachments: [
            {
              fields: [
                {
                  title: 'Version',
                  value: search_migration.version,
                  short: true
                },
                {
                  title: 'Name',
                  value: search_migration.name,
                  short: true
                },
                {
                  title: 'Completed',
                  value: search_migration.completed ? 'true' : 'false',
                  short: true
                },
                {
                  title: 'Started at',
                  value: search_migration.started_at,
                  short: true
                },
                {
                  title: 'Completed at',
                  value: search_migration.completed_at,
                  short: true
                },
                {
                  title: 'Obsolete',
                  value: search_migration.obsolete ? 'true' : 'false',
                  short: true
                },
                {
                  title: 'Migration state',
                  value: "```#{search_migration.migration_state.to_h}```",
                  short: true
                }
              ]
            }
          ]
        )
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
