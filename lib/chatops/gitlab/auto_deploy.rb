# frozen_string_literal: true

module Chatops
  module Gitlab
    class AutoDeploy
      TASK_PROJECT = 'gitlab-org/release/tools'

      def initialize(client = nil)
        @client = client
      end

      def tasks
        @tasks ||= @client
          .pipeline_schedules(TASK_PROJECT)
          .select { |s| s.description.start_with?('auto_deploy:') }
      end

      def pause
        update_tasks(active: false)
      end

      def unpause_prepare
        @client
          .edit_pipeline_schedule(TASK_PROJECT, prepare_task.id, active: true)
      end

      def pause_prepare
        @client
          .edit_pipeline_schedule(TASK_PROJECT, prepare_task.id, active: false)
      end

      def unpause
        update_tasks(active: true)
      end

      def update_tasks(attrs = {})
        ensure_tasks!

        tasks.map! do |task|
          @client.edit_pipeline_schedule(TASK_PROJECT, task.id, **attrs)
        end
      end

      private

      def prepare_task
        ensure_tasks!

        task = tasks.find { |t| t.description == 'auto_deploy:prepare' }

        raise "No prepare task was found in #{TASK_PROJECT}" unless task

        task
      end

      def ensure_tasks!
        return if tasks.any?

        raise "No auto_deploy tasks found in #{TASK_PROJECT}"
      end
    end
  end
end
