# frozen_string_literal: true

module Chatops
  module Gitlab
    class MergeRequestReleaseChecker
      SECURITY_PROJECT = 'gitlab-org/security/gitlab'
      CANONICAL_PROJECT = 'gitlab-org/gitlab'

      MONTHLY_RELEASE_VERSION_REGEX = /\A(?<major>\d+)\.(?<minor>\d+)\z/

      AUTO_DEPLOY_BRANCH_REGEX = /^\d+-\d+-auto-deploy-\d+$/

      def initialize(merge_request_iid, release_version, token)
        @mr_iid = merge_request_iid
        @version = release_version
        @token = token
      end

      def execute
        error = validate_args
        return response_message(error) if error

        result =
          if stable_branch_exists?
            check_commit_in_stable_branch(merge_request.merge_commit_sha)
          else
            check_commit_deployed_to_gprd(merge_request.merge_commit_sha)
          end

        response_message(result)
      end

      private

      attr_reader :mr_iid, :version, :token

      def validate_args
        return :invalid_version_string unless MONTHLY_RELEASE_VERSION_REGEX.match?(version)

        return :mr_does_not_exist unless merge_request

        :mr_not_merged if merge_request.state != 'merged'
      end

      def production_client
        @production_client ||= Gitlab::Client.new(token: token)
      end

      def merge_request
        @merge_request ||= production_client.merge_request(CANONICAL_PROJECT, mr_iid)
      rescue ::Gitlab::Error::NotFound
        nil
      end

      def stable_branch_name
        @stable_branch_name ||= version.tr('.', '-') << '-stable-ee'
      end

      def stable_branch_exists?
        production_client.branch(SECURITY_PROJECT, stable_branch_name)

        true
      rescue ::Gitlab::Error::NotFound
        false
      end

      def gprd_environment_status
        rails = Gitlab::Deployments
          .new(production_client, SECURITY_PROJECT)
          .upcoming_and_current('gprd')

        rails.map do |ee|
          {
            role: 'gprd',
            revision: (ee&.short_sha || 'unknown'),
            branch: (ee&.ref || 'unknown'),
            status: (ee&.status || 'unknown')
          }
        end
      end

      def branches_containing_commit(sha)
        production_client
          .commit_refs(SECURITY_PROJECT, sha, type: 'branch', per_page: 100)
          .auto_paginate
      rescue ::Gitlab::Error::NotFound
        []
      end

      def auto_deploy_branches_containing_commit(sha)
        branches_containing_commit(sha)
          .select { |b| b.name.match?(AUTO_DEPLOY_BRANCH_REGEX) }
      end

      def check_commit_in_stable_branch(sha)
        branch_contains_commit =
          branches_containing_commit(sha)
            .select { |b| b.name == stable_branch_name }
            .length >= 1

        if branch_contains_commit
          :commit_present_in_stable_branch
        else
          :commit_not_present_in_stable_branch
        end
      end

      def check_commit_deployed_to_gprd(sha)
        env_containing_sha =
          gprd_environment_status.select do |environment|
            auto_deploy_branches_containing_commit(sha).any? do |auto_deploy_branch|
              environment[:branch] == auto_deploy_branch.name && environment[:status] == 'success'
            end
          end

        if env_containing_sha.length >= 1
          :commit_deployed_to_gprd
        else
          :commit_not_deployed_to_gprd
        end
      end

      def slack_link(link, text)
        "<#{link}|#{text}>"
      end

      def mr_slack_link
        slack_link("https://gitlab.com/#{CANONICAL_PROJECT}/-/merge_requests/#{mr_iid}", "Merge request #{mr_iid}")
      end

      def stable_branch_link
        slack_link("https://gitlab.com/#{SECURITY_PROJECT}/-/tree/#{stable_branch_name}", 'stable branch')
      end

      def response_message(code)
        messages = {
          invalid_version_string:
            "'#{version}' is not a valid monthly release version. Monthly release versions " \
            'look like 10.0 or 14.2',

          mr_does_not_exist: "#{mr_slack_link} does not exist.",

          mr_not_merged: "#{mr_slack_link} has not been merged as yet!",

          commit_present_in_stable_branch:
            "#{mr_slack_link} has been included in the #{stable_branch_link}. This MR " \
            "will be released in #{version}.",

          commit_not_present_in_stable_branch:
            "#{mr_slack_link} has not been included in the #{stable_branch_link}. " \
            "The MR _will not_ be released in #{version}.",

          commit_deployed_to_gprd:
            "#{mr_slack_link} has been deployed to gprd. It will most likely be " \
            "included in release #{version}.",

          commit_not_deployed_to_gprd:
            "#{mr_slack_link} has not yet been deployed to gprd. It cannot be included " \
            'in the monthly release until it is deployed to gprd.'
        }

        return messages[code] if messages.key?(code)

        raise "Did you forget to add a message string? The message string for '#{code}' is unknown."
      end
    end
  end
end
