# frozen_string_literal: true

module Chatops
  module Release
    # Common configuration and utilities for commands in release-tools.
    module Command
      # rubocop:disable Style/RegexpLiteral
      VERSION_REGEX = %r{
        \A
        (?<major>\d+)\.
        (?<minor>\d+)\.
        (?<patch>\d+)
        (-rc(?<rc>\d+))?
        \z
      }x
      # rubocop:enable Style/RegexpLiteral

      TARGET_PROJECT = 'gitlab-org/release-tools'
      TARGET_REF = 'master'

      TriggerResult = Struct.new(:status, :url) do
        def success?
          status == :success
        end
      end

      def trigger_release(version,
                          task_name = self.class.command_name,
                          params = {})
        pipeline = run_trigger(version, task_name, params)
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

      def required_argument(index, name)
        arguments.fetch(index) do
          raise(ArgumentError, "You must specify the #{name}!")
        end
      end

      def validate_version!(version)
        return if VERSION_REGEX.match?(version)

        raise ArgumentError, "Invalid version provided: #{version}"
      end

      def run_trigger(version, task_name, params = {})
        params[:TEST] = 'true' if options[:dry_run]

        client.run_trigger(
          TARGET_PROJECT,
          env.fetch('RELEASE_TRIGGER_TOKEN'),
          TARGET_REF,
          params.merge(
            CHAT_CHANNEL: channel,
            RELEASE_USER: env.fetch('GITLAB_USER_LOGIN', ''),
            RELEASE_VERSION: version,
            TASK: task_name
          )
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
