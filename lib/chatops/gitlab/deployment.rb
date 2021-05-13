# frozen_string_literal: true

module Chatops
  module Gitlab
    class Deployment
      extend Forwardable

      def_delegators :@response, :ref, :sha, :status

      def initialize(api_response)
        @response = api_response
      end

      def package
        ref.sub('+', '-')
      end

      def short_sha
        sha[0...11]
      end

      def running?
        status == 'running'
      end

      def success?
        status == 'success'
      end

      def failed?
        status == 'failed'
      end
    end
  end
end
