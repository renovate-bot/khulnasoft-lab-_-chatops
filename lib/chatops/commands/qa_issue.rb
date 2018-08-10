# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in release-tools that creates a QA issue for the
    # specified comparison range.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/chatops.md#qa_issue
    class QaIssue
      include Command
      include Release::Command

      TAG_REGEX = /\Av\d+\.\d+\.\d+(-rc\d+)?\z/

      usage "#{command_name} [from..to]"
      description 'Create a QA issue.'

      options do |o|
        o.bool '--security', 'Create a QA issue for a security release.',
               default: false
      end

      def perform
        comparison = required_argument(0, 'comparison')
        tags = comparison.split('..').slice(0, 2)

        validate_comparison!(tags)

        task_name = self.class.command_name.dup
        task_name.prepend('security_') if options[:security]

        trigger_release(tags.join(','), task_name)
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
