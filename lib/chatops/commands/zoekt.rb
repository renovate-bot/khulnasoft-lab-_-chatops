# frozen_string_literal: true

module Chatops
  module Commands
    class Zoekt
      include Command
      include GitlabEnvironments
      include ::SemanticLogger::Loggable

      COMMANDS = %w[force_index_project indexed_namespace_create indexed_namespace_delete].freeze

      description 'Managing Zoekt shards and indexed namespaces'

      EXAMPLES = <<~EXAMP
        Examples:

          Adding a namespace to be indexed in a shard

            indexed_namespace_create <shard_id> <namespace_id>

          Force indexing for a project

            force_index_project <project_id>

          Deleting an indexed namespace from the shard

            indexed_namespace_delete <shard_id> <namespace_id>
      EXAMP

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator EXAMPLES

        GitlabEnvironments.define_environment_options(o)
      end

      def perform
        command = arguments.first

        if COMMANDS.include?(command)
          send(command)
        else
          unsupported_command
        end
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      private

      def indexed_namespace_create
        shard_id = required_integer_argument(1, :shard_id)
        namespace_id = required_integer_argument(2, :namespace_id)

        result = gitlab_client.zoekt_shard_indexed_namespaces_create(shard_id: shard_id, namespace_id: namespace_id)

        if result
          'Successfully created indexed namespace for ' \
          "shard #{result.zoekt_shard_id} and namespace #{result.namespace_id}"
        else
          "Failed to create the indexed namespace for shard #{shard_id} and namespace #{namespace_id}"
        end
      end

      def indexed_namespace_delete
        shard_id = required_integer_argument(1, :shard_id)
        namespace_id = required_integer_argument(2, :namespace_id)

        result = gitlab_client.zoekt_shard_indexed_namespaces_delete(shard_id: shard_id, namespace_id: namespace_id)

        if result
          "Successfully deleted indexed namespace with shard #{shard_id} and namespace #{namespace_id}"
        else
          "Failed: Could not find Zoekt indexed namespace with shard_id: #{shard_id} and namespace_id: #{namespace_id}"
        end
      end

      def force_index_project
        project_id = required_integer_argument(1, :project_id)

        result = gitlab_client.zoekt_project_index(project_id: project_id)

        if result
          "Successfully triggered indexing for project #{project_id} with job_id \"#{result.job_id}\""
        else
          "Failed to trigger indexing for project #{project_id}"
        end
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The zoekt subcommand is invalid. The following subcommands are available:

          #{list}

          #{EXAMPLES}
        MESSAGE
      end

      def gitlab_client
        @gitlab_client ||= Gitlab::Client.new(token: environment.gitlab_token, host: environment.gitlab_host)
      end
    end
  end
end
