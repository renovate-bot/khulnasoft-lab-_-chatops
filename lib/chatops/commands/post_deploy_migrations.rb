# frozen_string_literal: true

module Chatops
  module Commands
    class PostDeployMigrations
      include Command
      include ::Chatops::Release::Command
      include ::SemanticLogger::Loggable

      COMMANDS = Set.new(%w[execute])

      options do |o|
        o.bool('--dry-run', 'Dry run mode')

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Execute post deploy migrations

              execute
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `post_deploy_migrations --help`.
        HELP
      end

      def execute
        response = run_trigger(POSTDEPLOY_PIPELINE: 'true')

        logger.info('Triggered post deploy migrations pipeline', url: response.web_url)

        "The post-deploy migration pipeline has started: #{response.web_url}"
      end
    end
  end
end
