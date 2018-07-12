# frozen_string_literal: true

module Chatops
  module Commands
    class QaIssue
      include Command
      include Release::Command

      TAG_REGEX = /\Av\d+\.\d+\.\d+(-rc\d+)?\z/

      usage "#{command_name} [from..to]"
      description 'Create a QA issue.'

      def perform
        comparison = required_argument(0, 'comparison')
        tags = comparison.split('..').slice(0, 2)

        validate_comparison!(tags)

        trigger_release(tags.join(','))
      end

      private

      def validate_comparison!(tags)
        if tags.size != 2
          raise ArgumentError,
                "Invalid comparison provided: #{tags.join('..')}"
        end

        tags.each do |tag|
          unless TAG_REGEX.match?(tag)
            raise ArgumentError, "Invalid tag provided: #{tag}"
          end
        end
      end
    end
  end
end
