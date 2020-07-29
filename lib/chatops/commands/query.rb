# frozen_string_literal: true

module Chatops
  module Commands
    class Query
      include Command

      description 'Obtains information about PostgreSQL queries stored in ' \
        'pg_stat_statements.'

      options do |o|
        o.string(
          '--host',
          'Connects to the given host instead of the default one'
        )

        o.separator <<~HELP.chomp

          Examples:

            Obtaining basic details of a query using its ID:

              query 2923518590

            Obtaining query details using a custom host:

              query --host 10.1.2.3 2923518590
        HELP
      end

      # The SQL query to execute for obtaining information about an existing SQL
      # query.
      QUERY = <<~SQL.strip
        SELECT pg_roles.rolname AS username,
          pg_database.datname AS database_name,
          pg_stat_statements.*
        FROM pg_stat_statements
        INNER JOIN pg_roles ON pg_roles.oid = pg_stat_statements.userid
        INNER JOIN pg_database ON pg_database.oid = pg_stat_statements.dbid
        WHERE queryid = %<query_id>i
      SQL

      # The base URL for Grafana links.
      GRAFANA_URL = 'https://dashboards.gitlab.net/d/000000232/' \
        'postgresql-query-drill-down?var-queryid=%<query_id>s'

      def perform
        id = arguments[0]

        return 'You must specify a query ID.' unless id

        unless valid_query_id?(id)
          return 'You must specify a numerical value as the query ID.'
        end

        row = database_connection
          .execute(format(QUERY, query_id: id))
          .first

        return 'No query exists for the given ID.' unless row

        upload_query_to_slack(row)
        submit_query_statistics(row)
      end

      # id - The ID given by the user as a String.
      def valid_query_id?(id)
        id.match?(/\A\d+\z/)
      end

      # Uploads a SQL query to Slack.
      #
      # row - The row retrieved from `pg_stat_statements`.
      def upload_query_to_slack(row)
        Slack::FileUpload
          .new(
            file: row['query'],
            type: :sql,
            channel: channel,
            token: slack_token,
            title: "SQL for query #{row['queryid']}"
          )
          .upload
      end

      # Submits the query statistics back to Slack.
      #
      # row - The row retrieved from `pg_stat_statements`.
      def submit_query_statistics(row)
        fields = attachment_fields(row)

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
            text: "Query statistics for query #{row['queryid']}:",
            attachments: [
              {
                title: 'Statistics',
                fields: fields,
                actions: [
                  {
                    type: :button,
                    text: 'View in Grafana',
                    url: grafana_url(row)
                  }
                ]
              }
            ]
          )
      end

      # Returns an Array containing attachment fields to use for a Slack
      # message.
      #
      # row - The row retrieved from `pg_stat_statements`.
      def attachment_fields(row)
        fields = []

        row.each do |key, value|
          next if key == 'query'

          value = "#{value} ms" if key.end_with?('_time')

          fields << {
            title: key,
            value: value,
            short: true
          }
        end

        fields
      end

      # Returns a URL that can be used to view query statistics in Grafana.
      def grafana_url(row)
        format(GRAFANA_URL, query_id: row['queryid'])
      end

      def database_connection
        Chatops::Database::ReadOnlyConnection
          .from_environment(database_environment_variables)
      end

      # Returns a Hash containing the environment variables to use for
      # connecting to the database.
      def database_environment_variables
        if options[:host]
          env.merge('DATABASE_HOST' => options[:host])
        else
          env
        end
      end
    end
  end
end
