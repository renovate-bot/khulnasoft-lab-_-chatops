# frozen_string_literal: true

module Chatops
  module Events
    class Client
      VALID_ENVS = %w[gstg gprd].freeze

      attr_reader :client

      def initialize(gitlab_env)
        unless VALID_ENVS.include?(gitlab_env)
          raise "Only #{VALID_ENVS.join(',')} are valid envs for sending events"
        end

        @gitlab_env = gitlab_env
        @client = HTTP.headers('Content-Type' => 'application/json')
          .basic_auth(user: es_user, pass: es_pass)
      end

      def send_event(message, fields: {})
        return unless check_vars

        data = {
          'time' => Time.now.utc.iso8601,
          'message' => message,
          'username' => gitlab_user_login,
          'source' => ci_job_name,
          'env' => @gitlab_env,
          'stage' => 'main'
        }

        data.update(fields)

        client.post(es_url + "/events-#{@gitlab_env}/_doc", json: data)
      end

      private

      def es_pass
        @es_pass ||= ENV['ES_NONPROD_EVENT_PASS']
      end

      def es_user
        @es_user ||= ENV.fetch('ES_NONPROD_EVENT_USER', 'events')
      end

      def es_url
        @es_url ||= ENV['ES_NONPROD_URL']
      end

      def ci_job_name
        @ci_job_name ||= ENV.fetch('CI_JOB_NAME', 'unknown')
      end

      def gitlab_user_login
        @gitlab_user_login ||= ENV.fetch('GITLAB_USER_LOGIN', 'unknown')
      end

      def check_vars
        es_pass && es_url
      end
    end
  end
end
