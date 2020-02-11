# frozen_string_literal: true

module Chatops
  module Commands
    class AutoDeploy
      include Chef::Config
      include Command
      include ::Chatops::Release::Command

      COMMANDS = Set.new(%w[pause prepare status tag unpause])

      SOURCE_HOST = 'https://gitlab.com'
      SOURCE_PROJECT = 'gitlab-org/gitlab'

      options do |o|
        o.bool '--security',
               'Act as a security release',
               default: false

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Disable all of the auto-deploy scheduled tasks

              pause

            Enable all of the auto-deploy scheduled tasks

              unpause

            Trigger `auto_deploy:prepare` in release-tools

              prepare

            Trigger `auto_deploy:tag` in release-tools

              tag

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

      def pause
        tasks = Gitlab::AutoDeploy.new(production_client).pause

        post_task_status(tasks)
      end

      def prepare
        trigger_release(nil, 'auto_deploy:prepare')
      end

      def tag
        params = { SECURITY: true } if options[:security]

        trigger_release(nil, 'auto_deploy:tag', params || {})
      end

      def unpause
        tasks = Gitlab::AutoDeploy.new(production_client).unpause

        post_task_status(tasks)
      end

      def status(sha = nil)
        envs = [
          environment_status('gprd'),
          environment_status('gprd-cny'),
          environment_status('gstg')
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

      def post_task_status(tasks)
        blocks = ::Slack::BlockKit.blocks

        blocks.section do |section|
          summary = 'Scheduled auto-deploy tasks have been '
          summary +=
            if tasks.all?(&:active)
              're-enabled.'
            else
              'temporarily disabled.'
            end

          section.mrkdwn(text: summary)
        end

        tasks.each do |task|
          text = "#{task_icon(task)} `#{task.description}`"
          text += " Next run: `#{task.next_run_at}`" if task.active

          blocks.section { |section| section.mrkdwn(text: text) }
        end

        slack_message.send(blocks: blocks.as_json)
      end

      def environment_status(role)
        client = client_from_role(role)
        version = client.version
        revision = version.revision

        # Get the auto-deploy ref for the deployed revision
        auto_deploy_branch = auto_deploy_branches(revision).first

        {
          host: client.host,
          version: version.version,
          revision: version.revision,
          branch: auto_deploy_branch&.name || nil,
          package: chef_client.package_version(role)
        }
      end

      def auto_deploy_branches(ref)
        # NOTE: We always use the production client, because staging is always
        # behind for the specified repository.
        production_client
          .commit_refs(SOURCE_PROJECT, ref, type: 'branch', per_page: 100)
          .auto_paginate
          .select { |b| b.name.match?(/^\d+-\d+-auto-deploy-\d+$/) }
      rescue ::Gitlab::Error::NotFound
        []
      end

      def post_commit_status(commit_sha, envs)
        blocks = []

        begin
          commit = production_client.commit(SOURCE_PROJECT, commit_sha)

          blocks << {
            type: 'section',
            text: Slack.markdown(
              "#{commit_link(commit.short_id)} #{commit.title}"
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
              ":exclamation: `#{commit_sha}` not found in `#{SOURCE_PROJECT}`."
            )
          }
        end

        slack_message.send(blocks: blocks)
      end

      def post_environment_status(envs)
        blocks = []

        envs.each_with_index do |env, idx|
          promotable_from = promotable_env_revision(envs, idx)
          revision_markdown = md_revision_field(env[:revision], promotable_from)

          blocks << {
            type: 'section',
            text: Slack.markdown(environment_link(env))
          }

          blocks << {
            type: 'section',
            fields: [
              Slack.markdown("*Version:* `#{env[:version]}`"),
              Slack.markdown(revision_markdown),
              Slack.markdown("*Branch:* #{branch_link(env[:branch])}"),
              Slack.markdown("*Package:* `#{env[:package]}`")
            ]
          }

          blocks << { type: 'divider' }
        end

        blocks.pop # Remove the last divider

        slack_message.send(blocks: blocks)
      end

      def client_from_role(role)
        case role
        when 'gprd'
          production_client
        when 'gprd-cny'
          canary_client
        when 'gstg'
          staging_client
        end
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
        token = ENV.fetch('GITLAB_STAGING_TOKEN', gitlab_token)

        @staging_client ||= Gitlab::Client
          .new(token: token, host: 'staging.gitlab.com')
      end

      def chef_client
        @chef_client ||= Chatops::Chef::Client
          .new(chef_username, chef_pem_key, chef_url)
      end

      def slack_message
        @slack_message ||= Slack::Message
          .new(token: slack_token, channel: channel)
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

      def task_icon(task)
        if task.active
          ':white_check_mark:'
        else
          ':double_vertical_bar:'
        end
      end

      def commit_link(sha)
        url = "#{SOURCE_HOST}/#{SOURCE_PROJECT}/commit/#{sha}"
        text = "`#{sha}`"

        "<#{url}|#{text}>"
      end

      def compare_link(prev_sha, sha)
        url = "#{SOURCE_HOST}/#{SOURCE_PROJECT}/compare/#{prev_sha}...#{sha}"
        text = "Compare with `#{prev_sha}`"

        "<#{url}|#{text}>"
      end

      def branch_link(branch)
        if branch
          url = "#{SOURCE_HOST}/#{SOURCE_PROJECT}/commits/#{branch}"
          text = "`#{branch}`"

          "<#{url}|#{text}>"
        else
          # Something other than an auto-deploy branch is deployed
          'Unknown'
        end
      end

      def promotable_env_revision(envs, idx)
        return if idx.zero?

        envs.dig(idx - 1, :revision)
      end

      def md_revision_field(current_revision, promotable_env_revision)
        revision_link = "*Revision:* #{commit_link(current_revision)}"

        return revision_link unless promotable_env_revision
        return revision_link if promotable_env_revision == current_revision

        whats_new_link = compare_link(promotable_env_revision, current_revision)

        "#{revision_link} - #{whats_new_link}"
      end
    end
  end
end
