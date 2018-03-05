# frozen_string_literal: true

module Chatops
  module Markdown
    # A Markdown code block.
    class Code
      attr_reader :value

      def initialize(value)
        @value = value.strip
      end

      def to_s
        if value.count("\n") >= 1
          "```\n#{value}\n```"
        else
          "`#{value}`"
        end
      end
    end
  end
end
