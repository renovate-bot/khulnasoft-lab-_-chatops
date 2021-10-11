# frozen_string_literal: true

module Chatops
  module Gitlab
    class TestsPipeline
      # The project where the end-to-end test full pipeline will be triggered for run against staging.gitlab.com
      STAGING_QUALITY_PROJECT = 'gitlab-org/quality/staging'

      # The project where the end-to-end test smoke pipeline will be triggered for run against gitlab.com
      PRODUCTION_QUALITY_PROJECT = 'gitlab-org/quality/production'

      def initialize(environment, options, feature_name, feature_value)
        @environment = environment
        @options = options
        @feature_name = feature_name
        @feature_value = feature_value
      end

      def trigger_end_to_end
        return unless should_trigger?

        trigger_variables = { feature_toggled: @feature_name,
                              feature_value: @feature_value,
                              gitlab_username: ENV.fetch('GITLAB_USER_LOGIN') }

        trigger_variables[:chat_user_id] = ENV.fetch('CHAT_USER_ID') if ENV.key?('CHAT_USER_ID')

        response = ops_client.run_trigger(quality_project_path,
                                          ops_e2e_trigger_token,
                                          'master',
                                          trigger_variables)

        response.web_url
      rescue StandardError => e
        "Failed to trigger end-to-end test pipeline: #{e.message}"
      end

      def should_trigger?
        ENV.key?('TRIGGER_E2E_TESTS') &&
          @feature_value != 'false' &&
          allowed_environment? &&
          allowed_user? &&
          allowed_group? &&
          allowed_project?
      end

      private

      def allowed_environment?
        staging? || production?
      end

      def allowed_user?
        @options[:user].nil? || @options[:user] == 'gitlab-qa'
      end

      def allowed_group?
        @options[:group].nil? || @options[:group] == 'gitlab-qa-sandbox-group'
      end

      def allowed_project?
        @options[:project].nil?
      end

      def ops_client
        @ops_client ||= Gitlab::Client
          .new(token: ENV.fetch('GITLAB_OPS_TOKEN'), host: 'ops.gitlab.net')
      end

      def ops_e2e_trigger_token
        if staging?
          ENV.fetch('STAGING_OPS_E2E_TRIGGER_TOKEN')
        elsif production?
          ENV.fetch('PROD_OPS_E2E_TRIGGER_TOKEN')
        else
          raise 'No e2e test pipeline trigger token available for this environment'
        end
      end

      def quality_project_path
        if staging?
          STAGING_QUALITY_PROJECT
        elsif production?
          PRODUCTION_QUALITY_PROJECT
        else
          raise 'No quality project path available for this environment'
        end
      end

      def staging?
        @environment == 'gstg'
      end

      def production?
        @environment == 'gprd'
      end
    end
  end
end
