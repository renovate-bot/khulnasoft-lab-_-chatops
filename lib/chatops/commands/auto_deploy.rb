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

            Check the deploy status of a specific commit

              status 6dc9ffbaa4a4e77facec1f2a1573bbbac2252066
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

      def status(sha = nil)
        envs = [
          environment_status(production_client),
          environment_status(canary_client),
          environment_status(staging_client)
        ]

        if sha
          auto_deploy_branches = auto_deploy_branches(sha)

          deployed = envs.select do |env|
            auto_deploy_branches.any? { |b| env[:branch] == b.name }
          end

          post_commit_status(sha, deployed)
        else
          post_environment_status(envs)
        end
      end

      private

      def environment_status(client)
        version = client.version
        revision = version.revision

        # Get the auto-deploy ref for the deployed revision
        auto_deploy_branch = auto_deploy_branches(revision).first

        {
          host: client.host,
          version: version.version,
          revision: version.revision,
          branch: auto_deploy_branch&.name || nil
        }
      end

      def auto_deploy_branches(ref)
        # NOTE: We always use the production client, because staging is always
        # behind for the specified repository.
        production_client
          .commit_refs(PROJECT, ref, type: 'branch')
          .select { |b| b.name.match?(/^\d+-\d+-auto-deploy-\d+$/) }
      rescue ::Gitlab::Error::NotFound
        []
      end

      def post_commit_status(commit_sha, envs)
        blocks = []

        begin
          commit = production_client.commit(PROJECT, commit_sha)

          blocks << {
            type: 'section',
            text: Slack.markdown(
              "*`#{commit_link(commit.short_id)}`* #{commit.title}"
            )
          }

          if envs.any?
            blocks << {
              type: 'context',
              elements: envs.map do |env|
                Slack.markdown(environment_link(env))
              end
            }
          else
            blocks << {
              type: 'context',
              elements: [
                Slack.markdown(
                  ':warning: Unable to find a deployed branch for this commit.'
                )
              ]
            }
          end
        rescue ::Gitlab::Error::NotFound
          blocks << {
            type: 'section',
            text: Slack.markdown(
              ":exclamation: `#{commit_sha}` not found in `#{PROJECT}`."
            )
          }
        end

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(blocks: blocks)
      end

      def post_environment_status(envs)
        blocks = []

        envs.each do |env|
          blocks << {
            type: 'section',
            text: Slack.markdown(environment_link(env))
          }

          blocks << {
            type: 'section',
            fields: [
              Slack.markdown("*Version:* `#{env[:version]}`"),
              Slack.markdown("*Revision:* #{commit_link(env[:revision])}"),
              Slack.markdown("*Branch:* #{branch_link(env[:branch])}")
            ]
          }

          blocks << { type: 'divider' }
        end

        blocks.pop # Remove the last divider

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(blocks: blocks)
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

      def environment_link(env)
        icon =
          case env[:host]
          when /staging/
            'building_construction'
          when /canary/
            'canary'
          else
            'party-tanuki'
          end

        ":#{icon}: <https://#{env[:host]}/|#{env[:host]}>"
      end

      def commit_link(sha)
        url = "https://gitlab.com/#{PROJECT}/commit/#{sha}"
        text = "`#{sha}`"

        "<#{url}|#{text}>"
      end

      def branch_link(branch)
        if branch
          url = "https://gitlab.com/#{PROJECT}/commits/#{branch}"
          text = "`#{branch}`"

          "<#{url}|#{text}>"
        else
          # Something other than an auto-deploy branch is deployed
          'Unknown'
        end
      end
    end
  end
end
