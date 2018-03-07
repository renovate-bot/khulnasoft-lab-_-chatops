# frozen_string_literal: true

module Chatops
  module Commands
    # Command for generating Grafana graphs.
    class Graph
      include Command

      DEFAULT_SINCE = 6

      usage "#{command_name} [CATEGORY] [GRAPH] [OPTIONS]"
      description 'Uploads a graph from Grafana to Slack'

      options do |o|
        o.integer(
          '--since',
          'The start time of the graph in hours leading up to the current time',
          default: DEFAULT_SINCE
        )

        o.separator(
          "\nAvailable Graphs:\n\n#{available_graphs_description}"
        )
      end

      # Returns a String describing all the categories and their graphs.
      def self.available_graphs_description
        categories = configuration.map do |category, graphs|
          entries = graphs.map do |name, details|
            "  * #{name}: #{details['description']}"
          end

          "#{category}:\n#{entries.join("\n")}"
        end

        categories.join("\n\n")
      end

      def self.configuration
        @configuration ||= YAML
          .load_file(File.join(Chatops.configuration_directory, 'graphs.yml'))
      end

      def perform
        category = required_argument(0, 'category')
        name = required_argument(1, 'name')
        config = configuration_for(category, name)
        graph = graph(config['dashboard'], config['panel'])
        file = graph.download
        url = graph.url

        upload(name, file)

        "The image has been uploaded. You can also view it in Grafana at #{url}"
      end

      # Uploads the given image to slack.
      #
      # name - The name of the graph.
      # file - A file containing the image.
      def upload(name, file)
        file_upload = Slack::FileUpload.new(
          file: file,
          type: :png,
          channel: channel,
          token: slack_token,
          title: "Grafana graph: #{name}"
        )

        file_upload.upload
      ensure
        file.close
      end

      # Returns a `Grafana::Graph` for the given dashboard and panel.
      #
      # dashboard - The name of the dashboard containing the graph.
      # panel_id - The ID of the panel that displays the graph.
      def graph(dashboard, panel_id)
        stop = Time.now.utc
        since = options[:since] || DEFAULT_SINCE
        start = stop - (since * 3_600)

        Grafana::Graph.new(
          dashboard: dashboard,
          panel_id: panel_id,
          token: grafana_token,
          variables: { from: start.to_i * 1_000, to: stop.to_i * 1_000 }
        )
      end

      def required_argument(index, name)
        arguments.fetch(index) do
          raise(
            ArgumentError,
            "You must specify the #{name} of the graph to render"
          )
        end
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

      def configuration_for(category, name)
        entry = self.class.configuration.dig(category, name)

        unless entry
          raise ArgumentError, "The graph #{category}:#{name} does not exist"
        end

        entry
      end
    end
  end
end
