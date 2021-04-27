# frozen_string_literal: true

module Chatops
  module Grafana
    # A Graph can be used to construct a link to a Grafana graph and download
    # it.
    class Graph
      # The host to use for generating graphs.
      HOST = 'https://dashboards.gitlab.net'

      # The ID of the Grafana organisation.
      ORGANISATION = 1

      # Error raised when the graph could not be downloaded from Grafana.
      DownloadError = Class.new(StandardError)

      # dashboard - The name of the dashboard containing the graph.
      # panel_id - The ID of the panel that contains the graph.
      # token - The API token to use for downloading the graph.
      # variables - Any query string parameters to set.
      def initialize(dashboard:, panel_id:, token:, variables: {})
        @dashboard = dashboard
        @panel_id = panel_id
        @token = token
        @variables = variables
      end

      # Returns the full URL of the graph.
      def url
        variables = {
          panelId: @panel_id,
          orgId: ORGANISATION,
          height: 500,
          width: 1000
        }.merge(@variables)

        params = variables.map { |k, v| "#{k}=#{v}" }.join('&')

        HOST + "/render/dashboard-solo/db/#{@dashboard}?#{params}"
      end

      # Downloads the graph to a temporary file.
      def download
        image_response = HTTP
          .auth("Bearer #{@token}")
          .get(url)

        raise DownloadError, 'Failed to download the image from Grafana' unless image_response.status == 200

        file = Tempfile.new(['graph', '.png'])

        file.write(image_response.body.to_s)
        file.rewind
        file
      end
    end
  end
end
