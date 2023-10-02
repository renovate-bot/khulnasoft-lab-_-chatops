# frozen_string_literal: true

module Chatops
  module GitlabEnvironments
    class Environment
      class << self
        attr_reader :dev, :staging, :staging_ref, :ops, :pre, :production

        def initialize_all!(env)
          @dev = new(host: DEV_HOST, token: env.fetch('GITLAB_DEV_TOKEN', nil), name: 'dev')
          @staging = new(host: STAGING_HOST, token: env.fetch('GITLAB_STAGING_TOKEN', nil), name: 'gstg')
          @staging_ref = new(host: STAGING_REF_HOST, token: env.fetch('GITLAB_STAGING_REF_TOKEN', nil),
                             name: 'gstg-ref')
          @ops = new(host: OPS_HOST, token: env.fetch('GITLAB_OPS_TOKEN', nil), name: 'ops')
          @pre = new(host: PRE_HOST, token: env.fetch('GITLAB_PRE_TOKEN', nil), name: 'pre')
          @production = new(host: PRODUCTION_HOST, token: env.fetch('GITLAB_TOKEN', nil), name: 'gprd')
        end
      end

      attr_reader :gitlab_host, :gitlab_token, :env_name

      def initialize(host:, token:, name:)
        @gitlab_host = host
        @gitlab_token = token
        @env_name = name
      end

      def dev?
        env_name == 'dev'
      end

      def staging?
        env_name == 'gstg'
      end

      def staging_ref?
        env_name == 'gstg-ref'
      end

      def ops?
        env_name == 'ops'
      end

      def pre?
        env_name == 'pre'
      end

      def production?
        env_name == 'gprd'
      end

      def api_client
        @api_client ||= Gitlab::Client.new(token: gitlab_token, host: gitlab_host)
      end
    end
  end
end
