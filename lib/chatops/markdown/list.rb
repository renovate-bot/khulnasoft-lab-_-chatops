# frozen_string_literal: true

module Chatops
  module Markdown
    # A list of values to format as a Markdown list.
    class List
      attr_reader :values

      def initialize(values)
        @values = values
      end

      def to_s
        "* #{values.join("\n* ")}"
      end
    end
  end
end
