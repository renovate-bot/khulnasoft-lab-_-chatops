# frozen_string_literal: true

module Chatops
  module Commands
    # Command for interacting with batched background migrations
    class BatchedBackgroundMigrations
      include Command
      include GitlabEnvironments

      COMMANDS = Set.new(%w[list resume])

      description 'Managing Batched Background Migrations'

      def perform
        command = arguments.first

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def list
        migrations.each do |migration|
          submit_batched_background_migration_details(migration)
        end
      end

      def resume
        id = arguments[1]

        migration = gitlab_client.resume_batched_background_migration(id)

        submit_batched_background_migration_details(migration)

        nil
      end

      private

      def submit_batched_background_migration_details(batched_background_migration)
        slack_client
          .send(
            attachments: [
              {
                fields: [
                  {
                    title: 'ID',
                    value: batched_background_migration.id,
                    short: true
                  },
                  {
                    title: 'Job class',
                    value: batched_background_migration.job_class_name,
                    short: true
                  },
                  {
                    title: 'Table',
                    value: batched_background_migration.table_name,
                    short: true
                  },
                  {
                    title: 'Status',
                    value: batched_background_migration.status,
                    short: true
                  },
                  {
                    title: 'Progress',
                    value: batched_background_migration.progress,
                    short: true
                  },
                  {
                    title: 'Created at',
                    value: batched_background_migration.created_at,
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

        <<~MESSAGE.strip
          The batched background migration subcommand is invalid. The following subcommands are available:

          #{list}

          Some examples:

          ```
          # Listing all batched background migrations:
          batched_background_migration list
        MESSAGE
      end

      def migrations
        @migrations ||= gitlab_client.batched_background_migrations
      end

      def slack_client
        @slack_client ||= Slack::Message.new(token: slack_token, channel: channel)
      end

      def gitlab_client
        @gitlab_client ||= Gitlab::Client.new(token: environment.gitlab_token, host: environment.gitlab_host)
      end
    end
  end
end
