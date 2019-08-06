# frozen_string_literal: true

module Chatops
  module Commands
    class AutoDeploy
      include Command

      COMMANDS = Set.new(%w[status])
      PROJECT = 'gitlab-org/gitlab-ee'

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check the status of all environments

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

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `release --help`.
        HELP
      end

      def status
        envs = [
          environment_status(production_client),
          environment_status(canary_client),
          environment_status(staging_client)
        ]

        blocks = []

        envs.each do |env|
          blocks << {
            type: 'section',
            text: Slack.markdown(
              ":#{env_icon(env[:host])}: <https://#{env[:host]}/|#{env[:host]}>"
            )
          }

          blocks << {
            type: 'section',
            fields: [
              Slack.markdown("*Version* `#{env[:version]}`"),
              Slack.markdown("*Revision* `#{env[:revision]}`"),
              Slack.markdown("*Branch* `#{env[:branch]}`")
            ]
          }

          blocks << { type: 'divider' }
        end

        blocks.pop # Remove the last divider

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(blocks: blocks)
      end

      private

      def environment_status(client)
        version = client.version
        revision = version.revision

        # Get the auto-deploy ref for the deployed revision
        #
        # NOTE: We always use the production client, because staging is always
        # behind for the specified repository.
        auto_deploy_branch = production_client
          .commit_refs(PROJECT, revision, type: 'branch')
          .detect { |b| b.name.match?(/^\d+-\d+-auto-deploy-\d+$/) }

        {
          host: client.host,
          version: version.version,
          revision: version.revision,
          branch: auto_deploy_branch.name
        }
      end

      def production_client
        @production_client ||= Gitlab::Client
          .new(token: gitlab_token)
      end

      def canary_client
        @canary_client ||= Gitlab::Client
          .new(token: gitlab_token, host: 'canary.gitlab.com')
      end

      def staging_client
        @staging_client ||= Gitlab::Client
          .new(token: gitlab_token, host: 'staging.gitlab.com')
      end

      def env_icon(host)
        case host
        when /staging/
          'building_construction'
        when /canary/
          'canary'
        else
          'party-tanuki'
        end
      end
    end
  end
end
