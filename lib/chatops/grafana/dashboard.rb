# frozen_string_literal: true

module Chatops
  module Grafana
    class Dashboard
      GRAFANA_URL = 'https://dashboards.gitlab.net'

      def initialize(token:)
        @token = token
      end

      def find_by_uid(uid)
        resp = HTTP
          .auth("Bearer #{@token}")
          .get("#{GRAFANA_URL}/api/dashboards/uid/#{uid}")

        resp_json = parse_response_body(resp)

        unless resp.status.ok?
          message = resp_json['message']
          raise "Failed to find dashboard with UID '#{uid}': #{message}"
        end

        resp_json
      end

      private

      def parse_response_body(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => ex
        raise "Failed to parse Grafana response #{response}; reason: #{ex}"
      end
    end
  end
end
