# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in the release-tools project that performs a release
    # for the specified version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/rake-tasks.md#releaseversion
    class Release
      include Command

      VERSION_REGEX = /\A\d+\.\d+\.\d+(-rc\d+)?\z/
      TARGET_PROJECT = 'gitlab-org/release-tools'
      TARGET_REF = 'master'

      usage "#{command_name} [VERSION]"
      description 'Tag a new version of GitLab.'

      options do |o|
        o.bool '--security', 'Perform a security release', default: false
      end

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        pipeline = run_trigger(version)
        jobs = pipeline_jobs(pipeline.id)

        if chatops_job?(jobs)
          "View `#{self.class.command_name}` progress at #{job_url(jobs.first)}"
        else
          'Pipeline triggered but unable to find `chatops` job: ' \
            "#{pipeline_url(pipeline)}"
        end
      end

      def pipeline_url(pipeline)
        "https://gitlab.com/#{TARGET_PROJECT}/pipelines/#{pipeline.id}"
      end

      def job_url(job)
        "https://gitlab.com/#{TARGET_PROJECT}/-/jobs/#{job.id}"
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

      def client
        @client ||= Gitlab::Client.new(token: gitlab_token)
      end

      def run_trigger(version)
        client.run_trigger(
          TARGET_PROJECT,
          env.fetch('RELEASE_TRIGGER_TOKEN'),
          TARGET_REF,
          RELEASE_USER: env.fetch('GITLAB_USER_LOGIN', ''),
          RELEASE_VERSION: version,
          TASK: task_name
        )
      end

      def task_name
        task = self.class.command_name

        if options[:security]
          "security_#{task}"
        else
          task
        end
      end

      def pipeline_jobs(pipeline_id)
        client.pipeline_jobs(TARGET_PROJECT, pipeline_id)
      end

      def chatops_job?(jobs)
        jobs.count == 1 && jobs.first.name == 'chatops'
      end
    end
  end
end
