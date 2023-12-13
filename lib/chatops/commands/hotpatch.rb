# frozen_string_literal: true

module Chatops
  module Commands
    class Hotpatch
      include Command

      PATCHER_PATH = 'gitlab-com/engineering/patcher'
      PATCH_ENVS = %w[gprd gprd-cny gstg gstg-cny].freeze
      GITLAB_HOST = 'ops.gitlab.net'
      PROD_PROJECT = 'https://gitlab.com/gitlab-com/gl-infra/production'
      PATCHER_PROJECT = "https://#{GITLAB_HOST}/#{PATCHER_PATH}".freeze

      usage "#{command_name} [OPTIONS]"
      description 'Prepares a hotpatch for GitLab.com'
      options do |o|
        o.integer(
          '--incident',
          'Incident for the patch, this number is required and should ' \
          'match the incident number in the production incident tracker. '\
          'If GitLab.com is down or you cannot provide a number, '\
          'any number will suffice. ex: `1234`',
          required: true
        )
        o.string(
          '--package',
          'Instead of using the default packages, ' \
          'set an explicit package version. ' \
          'This is necessary when the version ' \
          'that needs to be patched is not the version reported by ' \
          '/chatops run auto_deploy status`. '\
          'ex: `13.1.202006180140-d76aead293f.e70555ca117`'
        )
      end

      def perform
        operations = []

        operations << create_branch

        if options[:package]
          operations << create_file(options[:package], 'env unknown')
        else
          versions = []
          PATCH_ENVS.each do |env|
            version = chef_client.package_version(env)
            next if versions.include?(version)

            versions << version
            operations << create_file(version, env)
          end
        end

        operations << create_merge_request

        <<~PATCH_RESULT.strip
          Initiated a hot patch for incident <#{incident_link}|##{options[:incident]}>
          :swiss-tanuki: :swiss-tanuki: :swiss-tanuki:
          #{operations.map { |i| "• #{i}" }.join("\n")}

          Please see the <https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md|release docs> for instructions
        PATCH_RESULT
      end

      def chef_client
        @chef_client ||= Chatops::Chef::Client.new
      end

      def gitlab_client
        @gitlab_client ||= Gitlab::Client.new(
          token: ops_token, host: GITLAB_HOST
        )
      end

      def create_branch
        resp = gitlab_client.create_branch(PATCHER_PATH, branch_name, 'master')
        ":git-branch: <#{resp.web_url}|#{branch_name}>"
      rescue ::Gitlab::Error::BadRequest => e
        raise if e.response_status != 400

        ":information_source: Branch `#{branch_name}` already exists"
      end

      def create_file(package_version, env)
        file_path = "patches/#{package_version}/.gitkeep"
        resp = gitlab_client.create_file(
          PATCHER_PATH,
          file_path,
          branch_name,
          '',
          "Creating patch dir for #{package_version}"
        )
        "*#{env_text(env)}*: "\
          "<#{PATCHER_PROJECT}/-/tree/#{branch_name}/#{resp.file_path}|" \
          'patch directory>'
      rescue ::Gitlab::Error::BadRequest => e
        raise if e.response_status != 400

        ":information_source: *#{env_text(env)}*: "\
          "Directory <#{PATCHER_PROJECT}/-/tree/#{branch_name}/#{file_path}|" \
          "#{package_version}> already exists"
      end

      def create_merge_request
        resp = gitlab_client.create_merge_request(
          PATCHER_PATH,
          "Hot patch for #{incident_link}",
          source_branch: branch_name,
          target_branch: 'master',
          remove_source_branch: true,
          description: merge_request_description
        )
        ":mr: MR <#{resp.web_url}|!#{resp.iid}>"
      rescue ::Gitlab::Error::Conflict => e
        ":information_source: #{e.response_message.join(' ')}"
      end

      def branch_name
        @branch_name ||= "#{gitlab_user}-#{options[:incident]}"
      end

      def ops_token
        @ops_token ||= env.fetch('GITLAB_OPS_TOKEN')
      end

      def gitlab_user
        @gitlab_user ||= env.fetch('GITLAB_USER_LOGIN')
      end

      def incident_link
        "#{PROD_PROJECT}/-/issues/#{options[:incident]}"
      end

      def env_text(env)
        case env
        when 'gstg'
          'staging'
        when 'gprd'
          'production'
        when 'gprd-cny'
          'canary'
        when 'gstg-cny'
          'staging-canary'
        else
          'unknown env'
        end
      end

      private

      def merge_request_description
        <<~MR_DESC.strip
          @#{gitlab_user} has initiated a hot patch for incident #{incident_link}

          **NOTE: Hot patch should only proceed if GitLab.com is down or if there's evidence of an S1 security vulnerability being actively exploited. Patching is _extremely_ disruptive to our continuous delivery pipeline and should only be done in extreme circumstances.  For all changes that are not critical, please use the auto-deploy process.**

          Please see the [release-docs](https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md) for instructions

          # TODO

          * [ ] Disable auto-deployments by running `/chatops run deploy lock gprd-cny`
          * [ ] Ensure a developer is working on a fix, and the MR has the appropriate labels (e.g. `Pick into auto-deploy`)
          * [ ] Send the following Slack message
          ```
          @release-managers we have submitted a post-deployment patch that will be fixed in master with <MR Link>. As soon as this MR is merged we will need to create a new auto-deploy branch and wait for a build in the new auto-deploy branch before promoting to production.
          ```
          cc @gitlab-org/release/managers
        MR_DESC
      end
    end
  end
end
