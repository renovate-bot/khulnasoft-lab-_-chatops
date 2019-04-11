# frozen_string_literal: true

module Chatops
  module PagerDuty
    class Client
      ENDPOINT = 'https://api.pagerduty.com'

      attr_reader :client

      def initialize(token)
        @client = HTTP
          .auth("Token token=#{token}")
          .headers(
            'Content-Type' => 'application/json',
            'Accept' => 'application/vnd.pagerduty+json;version=2'
          )
      end

      def services(query = nil)
        params = query ? { query: query } : {}

        response = client
          .get("#{ENDPOINT}/services", params: params)

        JSON.parse(response.body).fetch('services', [])
      end

      # add total=true if debugging, limit can't be more than 100
      def oncalls
        request_params = { 'include[]' => 'users', 'limit' => '100' }
        response = client
          .get("#{ENDPOINT}/oncalls", params: request_params)

        JSON.parse(response.body).fetch('oncalls', [])
      end
    end
  end
end
