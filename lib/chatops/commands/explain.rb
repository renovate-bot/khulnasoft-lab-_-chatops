# frozen_string_literal: true

module Chatops
  module Commands
    # Command for obtaining information of SQL query plans.
    class Explain
      include Command

      # Error raised when a query is very clearly dangerous.
      UnsafeQueryError = Class.new(StandardError)

      # Error raised whenever we're unable to visualise a query plan.
      QueryVisualisationError = Class.new(StandardError)

      description 'Obtains the query plan of a SQL query, ' \
        'optionally visualising it using explain.depesz.com'

      usage "#{command_name} [QUERY | URL] [OPTIONS]"

      options do |o|
        o.bool '--visual', 'Visualises the query plan'

        o.separator <<~HELP.chomp

          Examples:

            Obtaining the query plan of a SQL query:

              explain SELECT COUNT(*) FROM users

            If a query contains single or double quotes then you must quote the
            entire query:

              explain "SELECT COUNT(*) FROM users WHERE username = 'alice'"

            You can also get an EXPLAIN plan for a URL. This can be useful when
            the input URL is too large to be sent as a Slack message:

              explain https://example.com/my-query.sql
        HELP
      end

      # A regex indicating clearly dangerous queries that should never be
      # executed.
      UNSAFE_PATTERN = /\A(DELETE|DROP|ALTER|UPDATE|INSERT|CREATE)/i

      # The host to use for visualising query plans.
      EXPLAIN_HOST = 'https://explain.depesz.com'

      def perform
        query = arguments.join(' ').strip
        query = download_query(query) if query.start_with?('http')

        if clearly_dangerous?(query)
          raise(
            UnsafeQueryError,
            "The query #{query.inspect} is not safe to execute"
          )
        end

        upload_explain_plan_for(query)
      end

      # Submits the EXPLAIN output for the given query.
      #
      # query - The SQL query to explain.
      def upload_explain_plan_for(query)
        plan = database_connection
          .execute("EXPLAIN (ANALYZE, BUFFERS) #{query}")
          .map { |row| row['QUERY PLAN'] }
          .join("\n")

        url = url_for_visualised_plan(plan) if options[:visual]

        upload_plan(plan, url)
      end

      # Returns the URL for a visualised query plan.
      #
      # plan - The query plan to visualise.
      def url_for_visualised_plan(plan)
        response = HTTP.post(EXPLAIN_HOST, form: { plan: plan })

        unless response.status == 302
          raise(
            QueryVisualisationError,
            'Failed to submit the query plan to explain.depesz.com'
          )
        end

        EXPLAIN_HOST + response.headers['Location']
      end

      def database_connection
        Database::ReadOnlyConnection.from_environment(env)
      end

      # Uploads a query plan to Slack.
      #
      # plan - The query plan to upload as a String.
      # url - An optional URL to explain.depesz.com.
      def upload_plan(plan, url = nil)
        comment =
          if url
            "A visual representation of the plan can be found <#{url}|here>."
          end

        Slack::FileUpload
          .new(
            file: plan,
            type: :text,
            channel: channel,
            token: slack_token,
            title: 'EXPLAIN output',
            comment: comment
          )
          .upload
      end

      # Downloads a query to execute from the given URL.
      def download_query(url)
        HTTP.get(url).body.to_s
      end

      # Checks if a query is clearly dangerous or not.
      #
      # While queries are executed in read-only mode this method serves as a
      # simple way of catching queries that are clearly not meant to be run
      # (e.g. a query that deletes data).
      def clearly_dangerous?(query)
        query.match?(UNSAFE_PATTERN)
      end
    end
  end
end
