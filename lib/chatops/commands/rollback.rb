# frozen_string_literal: true

module Chatops
  module Commands
    class Rollback
      include Command
      include GitlabEnvironments

      COMMANDS = Set.new(%w[check]).freeze
      ENVIRONMENTS = %w[gprd gprd-cny gstg].freeze

      SOURCE_PROJECT = 'gitlab-org/security/gitlab'

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check if the latest staging deploy can be rolled back

              check gstg
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

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `release --help`.
        HELP
      end

      def check(env)
        unless ENVIRONMENTS.include?(env)
          return "Invalid environment `#{env}`, " \
            "expected `#{ENVIRONMENTS.join(', ')}`"
        end

        current, previous = production_client
          .latest_deployments(SOURCE_PROJECT, env, limit: 2)

        compare = production_client.compare(
          SOURCE_PROJECT,
          previous.sha,
          current.sha
        )

        blocks = ::Slack::BlockKit.blocks
        blocks.header(text: ":#{env_icon(env)}: #{env}", emoji: true)

        Gitlab::RollbackCheck
          .new(compare)
          .execute
          .slack_block(blocks)

        blocks.section do |s|
          lines = [
            "*Current:* #{commit_link(current.sha)}",
            "*Previous:* #{commit_link(previous.sha)}",
            "*Compare:* #{compare_link(previous.sha, current.sha)}"
          ]

          s.mrkdwn(text: lines.join("\n"))
        end

        slack_message.send(blocks: blocks.as_json)
      end

      private

      def production_client
        @production_client ||= Gitlab::Client
          .new(token: gitlab_token)
      end

      def slack_message
        @slack_message ||= Slack::Message
          .new(token: slack_token, channel: channel)
      end

      def commit_link(sha)
        text = sha[0...11]
        url = "https://gitlab.com/#{SOURCE_PROJECT}/-/commit/#{sha}"

        "<#{url}|`#{text}`>"
      end

      def compare_link(from, to)
        comparison = "#{from}...#{to}"
        url = "https://gitlab.com/#{SOURCE_PROJECT}/-/compare/#{comparison}"

        "<#{url}|`#{from[0...11]}...#{to[0...11]}`>"
      end
    end
  end
end
