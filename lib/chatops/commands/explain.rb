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

      options do |o|
        o.bool '--visual', 'Visualises the query plan'
      end

      # A regex indicating clearly dangerous queries that should never be
      # executed.
      UNSAFE_PATTERN = /\A(DELETE|DROP|ALTER|UPDATE|INSERT)/i

      # The host to use for visualising query plans.
      EXPLAIN_HOST = 'https://explain.depesz.com'

      def perform
        query = arguments.join(' ').strip

        if clearly_dangerous?(query)
          raise(
            UnsafeQueryError,
            "The query #{query.inspect} is not safe to execute"
          )
        end

        explain_plan_for(query)
      end

      # Returns the EXPLAIN output for the given query.
      #
      # query - The SQL query to explain.
      def explain_plan_for(query)
        plan = database_connection
          .execute("EXPLAIN (ANALYZE, BUFFERS) #{query}")
          .map { |row| row['QUERY PLAN'] }
          .join("\n")

        output = Markdown::Code.new(plan).to_s

        if options[:visual]
          url = url_for_visualised_plan(plan)

          output += "\n\nVisualised: #{url}"
        end

        output
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
        Database::ReadOnlyConnection.new(
          host: env['DATABASE_HOST'] || 'localhost',
          port: env['DATABASE_PORT'] || 5432,
          user: env['DATABASE_USER'],
          password: env['DATABASE_PASSWORD'],
          database: env.fetch('DATABASE_NAME')
        )
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
