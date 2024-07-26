# frozen_string_literal: true

module Chatops
  module Commands
    class Orchestrator
      include Command
      include ::SemanticLogger::Loggable

      COMMANDS = Set.new(%w[enable disable status])
      CONSUL_KEY = 'group-delivery/deployment/orchestrator'

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Enable deployment orchestrator

              enable

            Disable deployment orchestrator

              disable

            View orchestrator status

              status
        HELP
      end

      def consul_client
        @consul_client ||= Chatops::Consul::Client.new
      end

      def username
        @username ||= env.fetch('GITLAB_USER_LOGIN')
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

          For more information run `orchestrator --help`.
        HELP
      end

      def enable
        status = {
          "status" => "enabled",
          "datetime" => Time.now,
          "release_manager" => username
        }

        consul_client.put(CONSUL_KEY, JSON.generate(status))

        logger.info('Orchestrator enabled}')

        "Orchestrator enabled"
      end

      def disable
        status = {
          "status" => "disabled",
          "datetime" => Time.now,
          "release_manager" => username
        }

        consul_client.put(CONSUL_KEY, JSON.generate(status))

        logger.info('Orchestrator disabled')

        "Orchestrator disabled"
      end

      def status
        status = JSON.parse(consul_client.get(CONSUL_KEY))

        logger.info('Orchestrator status is...', status: status["status"])

        "Orchestrator status is #{status['status']}"
      rescue Chatops::Consul::Client::KeyNotFoundError => ex
        logger.error("Failed to retrieve orchestrator status: #{ex.message}")
        "Failed to retrieve orchestrator status: #{ex.message}"
      end
    end
  end
end
