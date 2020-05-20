# frozen_string_literal: true

module Chatops
  module Grafana
    class Annotate
      GRAFANA_URL = 'https://dashboards.gitlab.net'
      ANNOTATE_RETRIES = 3
      ANNOTATE_RETRY_INTERVAL = 3

      def initialize(token:)
        @token = token
      end

      def annotate!(text, tags: [], dashboard_id: nil)
        1.upto(ANNOTATE_RETRIES) do
          payload = {
            text: text,
            tags: tags
          }
          payload[:dashboardId] = dashboard_id if dashboard_id

          resp = HTTP
            .auth("Bearer #{@token}")
            .post("#{GRAFANA_URL}/api/annotations", json: payload)

          resp_json = parse_response_body(resp)

          return resp_json if resp.status.ok?

          sleep(ANNOTATE_RETRY_INTERVAL)
        end
        raise "Failed to annotate after #{ANNOTATE_RETRIES} retries"
      end

      private

      def parse_response_body(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise "Failed to parse Grafana response #{response}; reason: #{e}"
      end
    end
  end
end
