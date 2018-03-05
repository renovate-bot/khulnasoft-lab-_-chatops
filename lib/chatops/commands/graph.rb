# frozen_string_literal: true

module Chatops
  module Commands
    # Command for generating Grafana graphs.
    class Graph
      include Command

      description 'Uploads a graph from Grafana to Slack'

      # Error raised when the image could not be downloaded from Grafana.
      DownloadError = Class.new(StandardError)

      # Error raised when the image could not be uploaded.
      UploadError = Class.new(StandardError)

      # The host to use for generating graphs.
      GRAFANA_HOST = 'https://performance.gitlab.net'

      # The URL to upload images to.
      SLACK_UPLOAD_URL = 'https://slack.com/api/files.upload'

      # The ID of the Grafana organisation.
      GRAFANA_ORG = 1

      # The list of all supported graphs.
      GRAPHS = {
        'pg-dead-tuples' => ['postgres-tuple-statistics', 7],
        'pg-transactions' => ['postgres-stats', 5],
        'pg-load' => ['postgres-stats', 9],
        'pg-cpu' => ['postgres-stats', 13]
      }.freeze

      options do |o|
        o.integer(
          '--since',
          'The start time of the graph in hours leading up to the current time',
          default: 6
        )
      end

      def perform
        name = arguments.fetch(0) do
          raise(
            ArgumentError,
            'You must specify the name of the graph to render'
          )
        end

        dashboard, panel_id = GRAPHS.fetch(name) do
          raise(
            ArgumentError,
            "The graph #{name} does not exist. The following graphs " \
            "are available: #{GRAPHS.keys.sort.join(', ')}"
          )
        end

        url = url_for_graph(dashboard, panel_id)
        file = download_image(name, url)

        upload_image_to_slack(name, file)

        "The image has been uploaded. You can also view it in Grafana at #{url}"
      end

      # Uploads the given image to slack.
      #
      # name - The name of the graph.
      # file - A file containing the image.
      def upload_image_to_slack(name, file)
        response = HTTP.post(
          SLACK_UPLOAD_URL,
          form: {
            token: slack_token,
            channels: channel,
            file: HTTP::FormData::File.new(file.path),
            filename: "#{name}-#{Time.now.iso8601}.png",
            filetype: :png,
            title: "Grafana graph: #{name}"
          }
        )

        unless response.status == 200
          raise UploadError, 'Failed to upload the image to Slack'
        end
      ensure
        file.close
      end

      # Downloads an image to the local file system so it can be uploaded to
      # Slack.
      #
      # name - The name of the graph.
      # url - The URL of the image.
      def download_image(name, url)
        image_response = HTTP
          .auth("Bearer #{grafana_token}")
          .get(url)

        unless image_response.status == 200
          raise DownloadError, 'Failed to download the image from Grafana'
        end

        file = Tempfile.new([name, '.png'])

        file.write(image_response.body.to_s)
        file.rewind
        file
      end

      # Returns a URL for a Grafana graph.
      #
      # dashboard - The name of the dashboard containing the graph.
      # panel_id - The ID of the panel that displays the graph.
      # variables - Additional variables to pass such as the environment.
      def url_for_graph(dashboard, panel_id, variables = {})
        stop = Time.now.utc
        start = stop - (options[:since] * 3600)

        variables = variables.merge(
          from: start.to_i * 1000,
          to: stop.to_i * 1000,
          panelId: panel_id,
          orgId: GRAFANA_ORG,
          height: 500,
          width: 1000
        )

        params = variables.map { |k, v| "#{k}=#{v}" }.join('&')

        GRAFANA_HOST + "/render/dashboard-solo/db/#{dashboard}?#{params}"
      end

      def grafana_token
        env.fetch('GRAFANA_TOKEN')
      end

      def slack_token
        env.fetch('SLACK_TOKEN')
      end

      def channel
        env.fetch('CHAT_CHANNEL')
      end
    end
  end
end
