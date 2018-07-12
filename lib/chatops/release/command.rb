# frozen_string_literal: true

module Chatops
  module Release
    # Common configuration and utilities for commands in release-tools.
    module Command
      TARGET_PROJECT = 'gitlab-org/release-tools'
      TARGET_REF = 'master'

      TriggerResult = Struct.new(:status, :url) do
        def success?
          status == :success
        end
      end

      def pipeline_url(pipeline)
        "https://gitlab.com/#{TARGET_PROJECT}/pipelines/#{pipeline.id}"
      end

      def job_url(job)
        "https://gitlab.com/#{TARGET_PROJECT}/-/jobs/#{job.id}"
      end

      def trigger_release(version, task_name = self.class.command_name)
        pipeline = run_trigger(version, task_name)
        jobs = pipeline_jobs(pipeline.id)

        result =
          if chatops_job?(jobs)
            TriggerResult.new(:success, job_url(jobs.first))
          else
            TriggerResult.new(:failure, pipeline_url(pipeline))
          end

        if block_given?
          yield result
        elsif result.success?
          "View `#{self.class.command_name}` progress at #{result.url}"
        else
          "Pipeline triggered but unable to find `chatops` job: #{result.url}"
        end
      end

      private

      def run_trigger(version, task_name)
        client.run_trigger(
          TARGET_PROJECT,
          env.fetch('RELEASE_TRIGGER_TOKEN'),
          TARGET_REF,
          RELEASE_USER: env.fetch('GITLAB_USER_LOGIN', ''),
          RELEASE_VERSION: version,
          TASK: task_name
        )
      end

      def client
        @client ||= Gitlab::Client.new(token: gitlab_token)
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
