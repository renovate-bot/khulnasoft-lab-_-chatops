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

          For more information run `rollback --help`.
        HELP
      end

      def check(env_name)
        unless ENVIRONMENTS.include?(env_name)
          return "Invalid environment `#{env_name}`, " \
            "expected `#{ENVIRONMENTS.join(', ')}`"
        end

        current, previous = *latest_deployments(env_name)
        comparison = compare(current, previous)

        blocks = ::Slack::BlockKit.blocks
        blocks.header(text: ":#{env_icon(env_name)}: #{env_name}", emoji: true)

        Gitlab::RollbackCheck
          .new(comparison)
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

        blocks.context { |c| c.mrkdwn(text: handbook_link) }

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

      def latest_deployments(env_name)
        production_client.latest_deployments(SOURCE_PROJECT, env_name, limit: 2)
      end

      def compare(current, previous)
        production_client.compare(SOURCE_PROJECT, previous.sha, current.sha)
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

      def handbook_link
        url = 'https://gitlab.com/gitlab-org/release/docs/-/blob/master/runbooks/rollback-a-deployment.md'
        ":book: <#{url}|View runbook>"
      end
    end
  end
end
