# frozen_string_literal: true

module Chatops
  module Commands
    class Rollback
      include Command
      include GitlabEnvironments

      COMMANDS = Set.new(%w[check]).freeze
      ENVIRONMENTS = %w[gprd gprd-cny gstg gstg-cny].freeze

      SOURCE_PROJECT = 'gitlab-org/security/gitlab'
      PACKAGE_PROJECT = 'gitlab-org/security/omnibus-gitlab'

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

      # rubocop:disable Metrics/AbcSize
      def check(env_name)
        unless ENVIRONMENTS.include?(env_name)
          return "Invalid environment `#{env_name}`, " \
            "expected `#{ENVIRONMENTS.join(', ')}`"
        end

        running = running_deployment(env_name)
        current, previous = *latest_deployments(env_name)
        comparison = compare(current, previous)

        blocks = ::Slack::BlockKit.blocks
        blocks.header(text: ":#{env_icon(env_name)}: #{env_name}", emoji: true)

        Gitlab::RollbackCheck
          .new(comparison, running)
          .execute
          .slack_block(blocks)

        rollback_flag =
          case env_name
          when 'gstg'
            ''
          when 'gprd'
            '--production'
          end

        blocks.section do |s|
          pkg_name = rollback_package(env_name)
          lines = [
            "*Current:* #{commit_link(current.sha)} " \
              "(#{compare_link(previous.sha, current.sha, 'compare to Previous')})",
            "*Previous:* #{commit_link(previous.sha)}",
            "*Previous package:* `#{pkg_name}`"
          ]

          if rollback_flag
            lines.push("*Rollback command:* `/chatops run deploy --rollback #{rollback_flag} #{pkg_name}`")
          end

          if running
            lines.prepend(
              "*New:* #{commit_link(running.sha)} " \
                "(#{compare_link(current.sha, running.sha, 'compare to Current')})"
            )
          end

          s.mrkdwn(text: lines.join("\n"))
        end

        blocks.context { |c| c.mrkdwn(text: handbook_link) }

        slack_message.send(blocks: blocks.as_json)
      end
      # rubocop:enable Metrics/AbcSize

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
        production_client.latest_deployments(
          SOURCE_PROJECT,
          env_name,
          status: 'success',
          limit: 2
        )
      end

      def running_deployment(env_name)
        # We only consider a deployment as running if it's the first deployment
        # regardless of status. This prevents a case where a deployment never
        # gets marked as failed and stays in the `running` state.
        production_client.latest_deployments(
          SOURCE_PROJECT,
          env_name,
          limit: 1
        ).detect { |dep| dep.status == 'running' }
      end

      def rollback_package(env_name)
        package = production_client.latest_deployments(
          PACKAGE_PROJECT,
          env_name,
          status: 'success',
          limit: 2
        ).last

        package.ref.sub('+', '-')
      end

      def compare(current, previous)
        production_client.compare(SOURCE_PROJECT, previous.sha, current.sha)
      end

      def commit_link(sha)
        text = sha[0...11]
        url = "https://gitlab.com/#{SOURCE_PROJECT}/-/commit/#{sha}"

        "<#{url}|`#{text}`>"
      end

      def compare_link(from, to, text = nil)
        comparison = "#{from}...#{to}"
        url = "https://gitlab.com/#{SOURCE_PROJECT}/-/compare/#{comparison}"
        text ||= "`#{from[0...11]}...#{to[0...11]}`"

        "<#{url}|#{text}>"
      end

      def handbook_link
        url = 'https://gitlab.com/gitlab-org/release/docs/-/blob/master/runbooks/rollback-a-deployment.md'
        ":book: <#{url}|View runbook>"
      end
    end
  end
end
