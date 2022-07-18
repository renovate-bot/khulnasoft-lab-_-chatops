# frozen_string_literal: true

require 'semantic_logger'

module Chatops
  include ::SemanticLogger::Loggable

  module Logger
    # Remove process info from the default Color formatter
    class NoProcessColorFormatter < SemanticLogger::Formatters::Color
      # The default warn color is `BOLD`, but `YELLOW` looks better
      def initialize(**args)
        args[:color_map] ||= ::SemanticLogger::Formatters::Color::ColorMap.new(
          warn: ::SemanticLogger::AnsiColors::YELLOW
        )

        super
      end

      def process_info
        nil
      end
    end

    # Remove process info from the Default formatter
    class NoProcessDefaultFormatter < SemanticLogger::Formatters::Default
      def process_info
        nil
      end
    end
  end
end

SemanticLogger.application = 'chatops'
SemanticLogger.default_level = ENV.fetch('LOG_LEVEL', 'debug').to_sym

if File.basename($PROGRAM_NAME) == 'rspec'
  # Overwrite each test run; meaningless in CI but nice for development
  SemanticLogger.add_appender(
    io: File.new('log/test.log', 'w'),
    formatter: Chatops::Logger::NoProcessDefaultFormatter.new
  )
else
  SemanticLogger.add_appender(
    io: $stdout,
    formatter: Chatops::Logger::NoProcessColorFormatter.new
  )

  if ENV['ELASTIC_URL']
    SemanticLogger.add_appender(
      appender: :elasticsearch_http,
      url: ENV['ELASTIC_URL'],
      index: 'chatops',
      host: ENV['CI_JOB_URL'],
      user: ENV.fetch('GITLAB_USER_LOGIN', nil),
      type: '_doc',

      # Give ES more time to respond over HTTP
      open_timeout: 5.0,
      read_timeout: 5.0,
      continue_timeout: 5.0
    )
  end
end
