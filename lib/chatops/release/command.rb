# frozen_string_literal: true

module Chatops
  module Release
    # Common configuration and utilities for commands in release-tools.
    module Command
      # rubocop:disable Style/RegexpLiteral
      # rubocop:disable Lint/MixedRegexpCaptureTypes
      VERSION_REGEX = %r{
        \A
        (?<major>\d+)\.
        (?<minor>\d+)\.
        (?<patch>\d+)
        (-rc(?<rc>\d+))?
        \z
      }x
      # rubocop:enable Style/RegexpLiteral
      # rubocop:enable Lint/MixedRegexpCaptureTypes

      TARGET_PROJECT = 'gitlab-org/release/tools'
      TARGET_REF = 'master'

      PIPELINE_SUCCESS = 'success'
      PIPELINE_FAILED = 'failed'

      TriggerResult = Struct.new(:status, :url) do
        def success?
          status == :success
        end
      end

      def trigger_release(version,
                          task_name = self.class.command_name,
                          params = {})
        pipeline = run_task(task_name, version, params)
        jobs = pipeline_jobs(pipeline.id)

        result =
          if chatops_job?(jobs)
            TriggerResult.new(:success, jobs.first.web_url)
          else
            TriggerResult.new(:failure, pipeline.web_url)
          end

        if block_given?
          yield result
        elsif result.success?
          "View `#{task_name}` progress at #{result.url}"
        else
          "Pipeline triggered but unable to find `chatops` job: #{result.url}"
        end
      end

      private

      def validate_version!(version)
        return if VERSION_REGEX.match?(version)

        raise ArgumentError, "Invalid version provided: #{version}"
      end

      def run_task(task_name, version, params = {})
        params[:SECURITY] = 'critical' if security_critical?

        run_trigger(
          params.merge(
            RELEASE_VERSION: version,
            TASK: task_name
          )
        )
      end

      def run_trigger(params = {})
        params[:TEST] = 'true' if options[:dry_run]
        params[:CHAT_CHANNEL] = channel
        params[:RELEASE_USER] = env.fetch('GITLAB_USER_LOGIN', '')

        logger = SemanticLogger[self.class.to_s]
        logger.info('Calling release tools trigger API', params: params)

        client.run_trigger(
          TARGET_PROJECT,
          env.fetch('RELEASE_TRIGGER_TOKEN') { env.fetch('CI_JOB_TOKEN') },
          TARGET_REF,
          params
        )
      end

      def client
        @client ||= Gitlab::Client.new(
          token: gitlab_ops_token,
          host: 'ops.gitlab.net'
        )
      end

      def pipeline_jobs(pipeline_id)
        client.pipeline_jobs(TARGET_PROJECT, pipeline_id)
      end

      def chatops_job?(jobs)
        jobs.count == 1 && jobs.first.name == 'chatops'
      end

      def security_critical?
        options[:security] && options[:critical]
      end
    end
  end
end
