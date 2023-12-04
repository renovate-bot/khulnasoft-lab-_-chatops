# frozen_string_literal: true

module Chatops
  module RubyWarning
    def warn(message)
      stacktrace = caller.detect { |line| line.include?('lib/chatops') }
      logger.warn(message, source: 'ruby_warnings', stacktrace: stacktrace)
    end

    private

    def logger
      @logger ||= SemanticLogger['Ruby']
    end
  end
end

# enable ruby deprecation warnings
Warning[:deprecated] = true

# override the warning message handler to log with SemanticLogger instead of
# writing to STDERR
Warning.singleton_class.prepend(Chatops::RubyWarning)
