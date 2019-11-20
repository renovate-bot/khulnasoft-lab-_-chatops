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

      def annotate!(text, tags: [])
        1.upto(ANNOTATE_RETRIES) do
          resp = HTTP
            .auth("Bearer #{@token}")
            .post(
              "#{GRAFANA_URL}/api/annotations",
              json: {
                text: text,
                tags: tags
              }
            )

          return resp.body_to_s if resp.status.ok?

          sleep ANNOTATE_RETRY_INTERVAL
        end
        raise "Failed to annotate after #{ANNOTATE_RETRIES} retries"
      end
    end
  end
end
