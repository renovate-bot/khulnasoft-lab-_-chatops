# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in the release-tools project that tags a specified
    # version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/rake-tasks.md#tagversion
    class Tag
      include Command
      include Release::Command

      VERSION_REGEX = /\A\d+\.\d+\.\d+(-rc\d+)?\z/

      usage "#{command_name} [VERSION]"
      description 'Tag a new version of GitLab.'

      options do |o|
        o.bool '--security', 'Tag a security release', default: false
      end

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        task_name = self.class.command_name
        task_name += '_security' if options[:security]

        pipeline = run_trigger(version, task_name)
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

      def validate_version!(version)
        return if VERSION_REGEX.match?(version)

        raise ArgumentError, "Invalid version provided: #{version}"
      end
    end
  end
end
