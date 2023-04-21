# frozen_string_literal: true

module Chatops
  module Commands
    class AutoDeploy
      include Command
      include GitlabEnvironments
      include ::Chatops::Release::Command
      include ::SemanticLogger::Loggable

      COMMANDS =
        Set.new(%w[pause prepare status security_status tag unpause blockers lock unlock])

      SOURCE_HOST = 'https://gitlab.com'

      RAILS_PROJECT = 'gitlab-org/security/gitlab'
      OMNIBUS_PROJECT = 'gitlab-org/security/omnibus-gitlab'

      options do |o|
        o.bool '--checks',
               'Include production checks in `status` output',
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

            Check the deploy status of one or more commits

              status 6dc9ffbaa4a4e77facec1f2a1573bbbac2252066 738f386d1c850607904fd9672e0ac3b5a32d1063

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

      def status(*shas)
        envs = [
          *environment_status('gprd'),
          *environment_status('gprd-cny'),
          *environment_status('gstg'),
          *environment_status('gstg-cny'),
          *environment_status('gstg-ref'),
          *environment_status('db/gstg'),
          *environment_status('db/gprd')
        ]

        if shas.empty?
          post_environment_status(envs)
          production_checks if options[:checks]
        else
          shas.each { |sha| sha_status(envs, sha) }

          nil
        end
      end

      def security_status
        query = { state: 'merged', target_branch: 'master', per_page: 50 }

        merged = production_client.merge_requests(RAILS_PROJECT, query).map(&:to_h)
        deployed = production_client.merge_requests(RAILS_PROJECT, query.merge(environment: 'gprd')).map(&:to_h)
        diff = merged - deployed

        if diff.empty?
          ":white_check_mark: All merged MRs in `#{RAILS_PROJECT}` have been deployed to Production."
        else
          blocks = ::Slack::BlockKit.blocks

          blocks.section do |section|
            section.mrkdwn(text: ":warning: Some merged MRs in `#{RAILS_PROJECT}` haven't been deployed to Production:")
          end

          blocks.section do |section|
            lines = diff.map do |mr|
              "• <#{mr['web_url']}|#{mr['references']['full']}>"
            end

            section.mrkdwn(text: lines.join("\n"))
          end

          slack_message.send(blocks: blocks.as_json)
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

      def sha_status(envs, sha)
        auto_deploy_branches = auto_deploy_branches(sha)

        deployed = envs.select do |env|
          logger.info('Deployment environment details', env: env[:role], branch: env[:branch], sha: env[:sha])

          auto_deploy_branches.any? do |b|
            env[:branch] == b.name &&
              env[:status] == 'success' &&
              commit_deployed?(b.name, env[:sha], sha)
          end
        end

        post_commit_status(sha, deployed)
      end

      def production_checks
        run_trigger(CHECK_PRODUCTION: 'true', PRODUCTION_CHECK_SCOPE: 'deployment')

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
        rails = Gitlab::Deployments
          .new(production_client, RAILS_PROJECT)
          .upcoming_and_current(role)

        omnibus = Gitlab::Deployments
          .new(production_client, OMNIBUS_PROJECT)
          .upcoming_and_current(role)

        rails.zip(omnibus).map do |ee, ob|
          {
            role: role,
            sha: (ee&.sha || 'unknown'),
            revision: (ee&.short_sha || 'unknown'),
            branch: (ee&.ref || 'unknown'),
            package: (ob&.package || 'unknown'),
            status: (ee&.status || 'unknown')
          }
        end
      end

      def auto_deploy_branches(ref)
        res = production_client
          .commit_refs(RAILS_PROJECT, ref, type: 'branch', per_page: 100)
          .auto_paginate
          .select { |b| b.name.match?(/^\d+-\d+-auto-deploy-\d+$/) }

        logger.info('Auto deploy branches', branches: res)

        res
      rescue ::Gitlab::Error::NotFound
        []
      end

      # `auto_deploy_branch` should be an auto-deploy branch that is known to contain both `deployed_sha` and `sha`.
      def commit_deployed?(auto_deploy_branch, deployed_sha, sha)
        # The commits returned by the API are in descending chronological order.
        # This will return the top 20 commits in the auto_deploy_branch.
        commits =
          production_client
            .commits(RAILS_PROJECT, ref_name: auto_deploy_branch)
            .map(&:id)

        # We assume that `deployed_sha` is in the top 20 commits on the auto_deploy_branch. This is a reasonable
        # assumption since auto deploy branches are short-lived branches, and the only way for commits to be added to
        # the branch is cherry-picking. We are unlikely to cherry-pick more than 20 commits into an auto-deploy branch.
        deployed_sha_index = commits.index(deployed_sha)
        logger.info('Deployed SHA index in commit list', deployed_sha_index: deployed_sha_index)

        # If `deployed_sha` is the latest in the auto_deploy_branch, it means that all commits in the branch have been
        # deployed.
        return true if deployed_sha_index.zero?

        commits_not_deployed = commits[0...deployed_sha_index]
        logger.info('Commits not deployed', commits_not_deployed: commits_not_deployed, sha: sha)

        # If `sha` is absent in the commits that were not deployed, and we assume that `sha` is present on the
        # auto_deploy_branch, it means that `sha` must be present further down the commit list, and has been deployed.
        !commits_not_deployed.include?(sha)
      end

      def post_commit_status(commit_sha, envs)
        blocks = ::Slack::BlockKit.blocks

        begin
          commit = production_client.commit(RAILS_PROJECT, commit_sha)

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
            s.mrkdwn(text: ":exclamation: `#{commit_sha}` not found in `#{RAILS_PROJECT}`.")
          end
        end

        slack_message.send(blocks: blocks.as_json)
      end

      def post_environment_status(envs)
        blocks = ::Slack::BlockKit.blocks

        envs.each_with_index do |env, idx|
          blocks.header(text: environment_text(env), emoji: true)

          blocks.section { |s| s.mrkdwn(text: ':ci_running: *New deployment*') } if env[:status] == 'running'

          blocks.section do |s|
            lines = [
              "*Revision:* #{commit_link(env[:revision])}",
              "*Branch:* #{branch_link(env[:branch])}",
              "*Package:* #{package_link(env[:package])}"
            ]

            if (comparison = promotable_env_revision(envs, idx))
              lines << "*Compare:* `#{comparison}`"
            end

            s.mrkdwn(text: lines.join("\n"))
          end
        end

        slack_message.send(blocks: blocks.as_json)
      end

      def production_client
        @production_client ||= Gitlab::Client
          .new(token: gitlab_token)
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
        ":#{env_icon(env[:role])}: #{env[:role]}"
      end

      def task_icon(task)
        if task.active
          ':white_check_mark:'
        else
          ':double_vertical_bar:'
        end
      end

      def commit_link(sha)
        url = "#{SOURCE_HOST}/#{RAILS_PROJECT}/-/commit/#{sha}"
        text = "`#{sha}`"

        "<#{url}|#{text}>"
      end

      def compare_link(prev_sha, sha)
        comparison = "#{prev_sha}...#{sha}"
        url = "#{SOURCE_HOST}/#{RAILS_PROJECT}/-/compare/#{comparison}"

        "<#{url}|#{comparison}>"
      end

      def branch_link(branch)
        if branch
          url = "#{SOURCE_HOST}/#{RAILS_PROJECT}/-/commits/#{branch}"
          text = "`#{branch}`"

          "<#{url}|#{text}>"
        else
          # Something other than an auto-deploy branch is deployed
          'Unknown'
        end
      end

      def package_link(package)
        if package
          ref = package.sub('-', '+')
          url = "#{SOURCE_HOST}/#{OMNIBUS_PROJECT}/-/commits/#{ref}"
          text = "`#{package}`"

          "<#{url}|#{text}>"
        else
          'Unknown'
        end
      end

      def promotable_env_revision(envs, idx)
        # Can't compare the last environment to anything
        return if idx >= envs.length - 1

        current = envs[idx]
        previous = envs[idx + 1]

        revisions = [current[:revision], previous[:revision]]

        # Can't compare identical revisions
        return if revisions.first == revisions.last

        # A running deployment needs to become the "to" argument
        #
        # See https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1756
        revisions.reverse! if current[:status] == 'running'

        compare_link(*revisions)
      end
    end
  end
end
