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
        versions = comparison.split('..')

        validate_comparison!(versions)

        pipeline = run_trigger(versions.join(','), self.class.command_name)
        jobs = pipeline_jobs(pipeline.id)

        if chatops_job?(jobs)
          "View `#{self.class.command_name}` progress at #{job_url(jobs.first)}"
        else
          'Pipeline triggered but unable to find `chatops` job: ' \
            "#{pipeline_url(pipeline)}"
        end
      end

      private

      def required_argument(index, name)
        arguments.fetch(index) do
          raise(ArgumentError, "You must specify the #{name}!")
        end
      end

      def validate_comparison!(versions)
        versions.each do |version|
          unless TAG_REGEX.match?(version)
            raise ArgumentError, "Invalid version provided: #{version}"
          end
        end
      end
    end
  end
end
