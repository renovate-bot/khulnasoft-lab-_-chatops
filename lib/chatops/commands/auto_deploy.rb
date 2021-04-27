# frozen_string_literal: true

module Chatops
  module Commands
    class AutoDeploy
      include Command
      include GitlabEnvironments
      include ::Chatops::Release::Command

      COMMANDS =
        Set.new(%w[pause prepare status tag unpause blockers lock unlock])

      SOURCE_HOST = 'https://gitlab.com'
      SOURCE_PROJECT = 'gitlab-org/security/gitlab'

      options do |o|
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

            Check if there are any ongoing issues that may block a deploy

              blockers
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
        tasks = Gitlab::AutoDeploy.new(ops_client).pause

        post_task_status(tasks)
      end

      def prepare
        trigger_release(nil, 'auto_deploy:prepare')
      end

      def tag
        trigger_release(nil, 'auto_deploy:tag')
      end

      def unpause
        tasks = Gitlab::AutoDeploy.new(ops_client).unpause

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
          production_checks
        end
      end

      def blockers
        production_checks
      end

      def lock(branch = nil)
        branch ||= environment_status('gprd')[:branch]

        return 'No auto-deploy branch to lock to could be found' unless branch

        Gitlab::AutoDeploy.new(ops_client).pause_prepare
        ops_client.update_variable(TARGET_PROJECT, 'AUTO_DEPLOY_BRANCH', branch)

        "Auto deploys have been locked to branch #{branch}"
      end

      def unlock
        Gitlab::AutoDeploy.new(ops_client).unpause_prepare

        'Preparing of auto-deploy branches has been resumed'
      end

      private

      def production_checks
        run_trigger(CHECK_PRODUCTION: 'true')

        'Production checks triggered, the results will appear shortly.'
      end

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
          role: role,
          revision: revision,
          branch: auto_deploy_branch&.name,
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
        blocks = ::Slack::BlockKit.blocks

        begin
          commit = production_client.commit(SOURCE_PROJECT, commit_sha)

          blocks.section do |s|
            s.mrkdwn(text: "#{commit_link(commit.short_id)} #{commit.title}")
          end

          blocks.context do |c|
            if envs.any?
              envs.each do |env|
                c.mrkdwn(text: environment_text(env))
              end
            else
              c.mrkdwn(text: ':warning: Unable to find a deployed branch for this commit.')
            end
          end
        rescue ::Gitlab::Error::NotFound
          blocks.section do |s|
            s.mrkdwn(text: ":exclamation: `#{commit_sha}` not found in `#{SOURCE_PROJECT}`.")
          end
        end

        slack_message.send(blocks: blocks.as_json)
      end

      def post_environment_status(envs)
        blocks = ::Slack::BlockKit.blocks

        envs.each_with_index do |env, idx|
          blocks.header(text: environment_text(env), emoji: true)
          blocks.section do |s|
            lines = [
              "*Revision:* #{commit_link(env[:revision])}",
              "*Branch:* #{branch_link(env[:branch])}",
              "*Package:* `#{env[:package]}`"
            ]

            if (comparison = promotable_env_revision(envs, idx))
              lines << "*Compare:* `#{comparison}`"
            end

            s.mrkdwn(text: lines.join("\n"))
          end
        end

        blocks.context do |c|
          link = 'https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1537'
          c.mrkdwn(text: <<~CONTEXT.tr("\n", ' '))
            :information_source: An ongoing deploy can make this information
            inaccurate. See <#{link}|gitlab-com/gl-infra/delivery#1537>.
          CONTEXT
        end

        slack_message.send(blocks: blocks.as_json)
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
        @canary_client ||= Gitlab::Client.new(
          token: gitlab_token,
          host: 'gitlab.com',
          httparty: {
            headers: { 'Cookie' => 'gitlab_canary=true' }
          }
        )
      end

      def staging_client
        token = ENV.fetch('GITLAB_STAGING_TOKEN', gitlab_token)

        @staging_client ||= Gitlab::Client
          .new(token: token, host: 'staging.gitlab.com')
      end

      def ops_client
        @ops_client ||= Gitlab::Client
          .new(token: gitlab_ops_token, host: 'ops.gitlab.net')
      end

      def chef_client
        @chef_client ||= Chatops::Chef::Client.new
      end

      def slack_message
        @slack_message ||= Slack::Message
          .new(token: slack_token, channel: channel)
      end

      def environment_text(env)
        ":#{env_icon(env[:role])}: #{env_host(env[:role])}"
      end

      def env_host(env)
        case env
        when 'gprd', 'gprd-cny'
          PRODUCTION_HOST
        when 'gstg'
          STAGING_HOST
        end
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
        comparison = "#{prev_sha}...#{sha}"
        url = "#{SOURCE_HOST}/#{SOURCE_PROJECT}/compare/#{comparison}"

        "<#{url}|#{comparison}>"
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
        # Can't compare the last environment to anything
        return if idx >= envs.length - 1

        current_rev = envs.dig(idx, :revision)
        next_rev = envs.dig(idx + 1, :revision)

        # Can't compare identical revisions
        return if current_rev == next_rev

        compare_link(current_rev, next_rev)
      end
    end
  end
end
