# frozen_string_literal: true

module Chatops
  module Commands
    # Command for interacting with batched background migrations
    class BatchedBackgroundMigrations
      include Command
      include GitlabEnvironments
      include ::SemanticLogger::Loggable

      COMMANDS = Set.new(%w[list resume status pause])

      description 'Managing Batched Background Migrations'

      options do |o|
        o.string(
          '--database',
          'Connects to the given database instead of the default one'
        )

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Listing 20 batched background migrations order by created_at (DESC)

              list

            Resume a batched background migration

              resume MIGRATION_ID

            Pause a batched background migration

              pause MIGRATION_ID

            Get a status of a background migration

              status MIGRATION_ID
        HELP

        GitlabEnvironments.define_environment_options(o)
      end

      def perform
        command = arguments.first

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def list
        return 'There are no migrations in the system' if migrations.empty?

        migrations.each do |migration|
          submit_batched_background_migration_details(migration)
        end

        nil
      end

      def resume
        return 'Please provide a migration ID to the resume command.' unless migration_id

        migration = gitlab_client.resume_batched_background_migration(migration_id, database: database)

        submit_batched_background_migration_details(migration)
      end

      def pause
        return 'Please provide a migration ID to the pause command.' unless migration_id

        migration = gitlab_client.pause_batched_background_migration(migration_id, database: database)

        submit_batched_background_migration_details(migration)
      end

      def status
        return 'Please provide a migration ID to the status command.' unless migration_id

        migration = gitlab_client.batched_background_migration(migration_id, database: database)

        submit_batched_background_migration_details(migration)
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      private

      def migration_id
        arguments[1]
      end

      def database
        options[:database] || 'main'
      end

      def submit_batched_background_migration_details(batched_background_migration)
        return 'Migration not found' unless batched_background_migration

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
                    title: 'Column',
                    value: batched_background_migration.column_name,
                    short: true
                  },
                  {
                    title: 'Status',
                    value: batched_background_migration.status,
                    short: true
                  },
                  {
                    title: 'Progress',
                    value: "#{batched_background_migration.progress}%",
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

        nil
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The batched background migration subcommand is invalid. The following subcommands are available:

          #{list}

          Some examples:

          ```
          # Listing 20 batched background migrations order by created_at (DESC):
          batched_background_migrations list

          # Resume a batched background migration:
          batched_background_migrations resume MIGRATION_ID

          # Pause a batched background migration:
          batched_background_migrations pause MIGRATION_ID

          # Get a status of a background migration:
          batched_background_migrations status MIGRATION_ID
        MESSAGE
      end

      def migrations
        @migrations ||= gitlab_client.batched_background_migrations(database: database)
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
