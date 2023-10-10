# frozen_string_literal: true

module Chatops
  module Database
    # A read-only database connection for executing SQL queries.
    class ReadOnlyConnection
      # Creates a new DB connection using the supplied environment variables.
      def self.from_environment(env = {})
        new(
          host: env['DATABASE_HOST'] || 'localhost',
          port: env['DATABASE_PORT'] || 5432,
          user: env['DATABASE_USER'],
          password: env['DATABASE_PASSWORD'],
          database: env.fetch('DATABASE_NAME')
        )
      end

      # host - The host to connect to.
      # port - The port to connect to.
      # user - The user to connect as, if any.
      # password - The password to use if authentication is required.
      # database - The database to connect to.
      def initialize(
        database:,
        host: 'localhost',
        port: 5432,
        user: nil,
        password: nil
      )
        @connection = PG.connect(
          host: host,
          port: port,
          user: user,
          password: password,
          dbname: database
        )
      end

      def execute(query)
        @connection.transaction do |conn|
          conn.exec('SET TRANSACTION READ ONLY')
          conn.exec(query)
        end
      end
    end
  end
end
