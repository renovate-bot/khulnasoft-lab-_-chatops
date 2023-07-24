# frozen_string_literal: true

module Chatops
  module Commands
    class Mirror
      include ::SemanticLogger::Loggable
      include Command

      TARGET_PROJECT = 'gitlab-org/release/tools'
      TARGET_REF = 'master'

      COMMANDS = Set.new(%w[status])

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check the status of all Security mirrors:

              status
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command, *arguments[1..-1])
        else
          unsupported_command
        end
      end

      def status
        params = {
          CHAT_CHANNEL: channel,
          MIRROR_STATUS: 'true'
        }

        logger.info('Calling release tools trigger API', params: params)

        client.run_trigger(
          TARGET_PROJECT,
          env.fetch('RELEASE_TRIGGER_TOKEN') { env.fetch('CI_JOB_TOKEN') },
          TARGET_REF,
          params
        )

        nil
      end

      private

      def client
        @client ||= Gitlab::Client.new(
          token: gitlab_ops_token,
          host: Chatops::GitlabEnvironments::OPS_HOST
        )
      end
    end
  end
end
