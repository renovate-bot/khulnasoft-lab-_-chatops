# frozen_string_literal: true

module Chatops
  module Commands
    # Directly map ChatOps to the release-tools `release` task namespace
    class Release
      include Command
      include ::Chatops::Release::Command

      OMNIBUS_DEV_PROJECT = 'gitlab/omnibus-gitlab'

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform release-related tasks.'

      COMMANDS = Set.new(
        %w[
          issue
          pending_backports
          merge
          prepare
          status
          sync_remotes
          tag
          close_issues
          tracking_issue
          build_status
          check
        ]
      )

      # rubocop: disable Metrics/BlockLength
      options do |o|
        o.bool '--security',
               'Act as a security release',
               default: false

        o.bool '--critical',
               'Act as a critical security release',
               default: false

        o.bool '--default-branch',
               'Merge MRs targeting the default branch',
               default: false

        o.bool '--master',
               'DEPRECATED: Use `--default-branch`',
               default: false

        o.bool '--dry-run',
               'Operate in dry-run mode, which will avoid making changes',
               default: false

        o.string '--gitaly-sha',
                 'The SHA to use for creating the Gitaly stable branch'

        o.string '--gitlab-sha',
                 'The SHA to use for creating the GitLab stable branch'

        o.string '--omnibus-sha',
                 'The SHA to use for creating the Omnibus stable branch'

        o.string '--cng-sha',
                 'The SHA to use for creating the CNG stable branch'

        o.string '--helm-sha',
                 'The SHA to use for creating the Helm stable branch'

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check if merge request `gitlab-org/gitlab!12345` will be included in 14.2.

              release check https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345 14.2

            Check in which version merge request `gitlab-org/security/gitlab!12345` was introduced.

              release check https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/12345

            Create a task issue for 1.2.3

              release issue 1.2.3

            Cherry-pick into preparation branches for 1.2.3-rc1

              release merge 1.2.3-rc1

            Merge security MRs

              release merge --security

            Prepare for 1.2.0

              release prepare 1.2.0

            Prepare for a security release

              release prepare --security

            Tag 1.2.3 as a security release

              release tag --security 1.2.3

            Tag 1.2.3 but use a different SHA for the Gitaly stable branch:

              release tag --gitaly-sha 123abc 1.2.3

            Sync default and auto-deploy branches after a security release

              release sync_remotes --security

            Close security implementation issues associated with the Security Release Tracking Issue

              release close_issues --security

            Create a Security Release Tracking Issue

              release tracking_issue --security
        HELP
      end
      # rubocop: enable Metrics/BlockLength

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

      def issue(version)
        validate_version!(version)

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def pending_backports
        trigger_release(nil, "#{namespace}:#{__method__}")
      end

      def merge(version = nil)
        return 'This command is only available with the --security option' unless options[:security]

        merge_default_branch =
          # Temporarily support either `--master` or `--default-branch`
          #
          # See https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1440
          if options[:master] || options[:default_branch]
            '1'
          else
            ''
          end

        trigger_release(
          version,
          "#{namespace}:#{__method__}",
          'MERGE_MASTER_SECURITY_MERGE_REQUESTS' => merge_default_branch
        )
      end

      def prepare(version = nil)
        validate_version!(version) unless options[:security] || version.nil?

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def status(version = nil)
        validate_version!(version) unless options[:security]

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def check(mr_url = nil, version = nil)
        if mr_url.nil?
          return 'You must specify a merge request URL and an optional self-managed release version. ' \
            'Ex: `release check https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345` ' \
            'or `release check https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345 14.2`'
        end

        ::Chatops::Gitlab::ReleaseCheck::Service
          .new(mr_url, version, gitlab_token)
          .execute
      end

      def build_status(*versions)
        return 'You must specify at least a single version' if versions.empty?

        blocks = ::Slack::BlockKit.blocks
        gitlab = Gitlab::Client
          .new(token: dev_token, host: GitlabEnvironments::DEV_HOST)

        versions.each do |version|
          ["#{version}+ce.0", "#{version}+ee.0"].each do |tag_name|
            blocks.section do |section|
              pipeline =
                gitlab.pipelines(OMNIBUS_DEV_PROJECT, ref: tag_name).first

              if pipeline
                statuses = pipeline_status_per_stage(gitlab, pipeline)
                output = "<#{pipeline.web_url}|*#{tag_name}*>\n" \
                  ":status_#{statuses['package-and-image']}: packaging " \
                  ":status_#{statuses['package-and-image-release']}: publishing"

                section.mrkdwn(text: output)
              else
                section.mrkdwn(
                  text: "*#{tag_name}*\nNo pipeline has been created yet"
                )
              end
            end
          end
        end

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(blocks: blocks.as_json)

        ''
      end

      def tag(version)
        validate_version!(version)

        trigger_release(version, "#{namespace}:#{__method__}", tag_params)
      end

      def sync_remotes(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def close_issues(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def tracking_issue(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      private

      TAG_REGEX = /\Av\d+\.\d+\.\d+(-rc\d+)?\z/

      def tag_params
        params = {}
        shas = []

        %w[gitaly gitlab omnibus cng helm].each do |key|
          if (value = options[:"#{key}_sha"])
            shas << "#{key}=#{value}"
          end
        end

        params[:STABLE_BRANCH_SOURCE_COMMITS] = shas.join(',') if shas.any?
        params
      end

      def namespace
        if options[:security]
          'security'
        else
          'release'
        end
      end

      def validate_comparison!(tags)
        if tags.size != 2
          raise ArgumentError,
                "Invalid comparison provided: #{tags.join('..')}"
        end

        tags.each do |tag|
          raise ArgumentError, "Invalid tag provided: #{tag}" unless TAG_REGEX.match?(tag)
        end
      end

      def dev_token
        env.fetch('GITLAB_DEV_TOKEN')
      end

      def pipeline_status_per_stage(gitlab, pipeline)
        gitlab
          .pipeline_jobs(pipeline.project_id, pipeline.id)
          .auto_paginate
          .group_by(&:stage)
          .each_with_object({}) do |(stage, jobs), memo|
            memo[stage] = status_for_jobs(jobs)
          end
      end

      def status_for_jobs(jobs)
        statuses = jobs.map do |j|
          j.status == 'failed' && j.allow_failure ? 'success' : j.status
        end.uniq

        %w[failed running created manual pending].each do |status|
          return status if statuses.include?(status)
        end

        'success'
      end
    end
  end
end
