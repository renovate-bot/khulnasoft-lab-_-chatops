# frozen_string_literal: true

module Chatops
  module Gitlab
    # HTTP client for the GitLab API.
    class Client
      DEFAULT_ENDPOINT = 'https://gitlab.com/api/v4'

      attr_reader :internal_client

      # token - The API token to use for authentication.
      # endpoint - The API endpoint to use.
      def initialize(token:, endpoint: DEFAULT_ENDPOINT)
        @internal_client = ::Gitlab::Client
          .new(endpoint: endpoint, private_token: token)
      end

      def features
        internal_client.get('/features').auto_paginate
      end

      # Sets a feature flag's state.
      #
      # name - The name of the flag.
      # value - The value to set for the flag.
      def set_feature(name, value)
        internal_client.post("/features/#{name}", body: { value: value })
      end
    end
  end
end
