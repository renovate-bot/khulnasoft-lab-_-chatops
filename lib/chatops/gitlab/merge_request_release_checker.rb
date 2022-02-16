# frozen_string_literal: true

module Chatops
  module Gitlab
    class MergeRequestReleaseChecker
      SECURITY_PROJECT = 'gitlab-org/security/gitlab'
      CANONICAL_PROJECT = 'gitlab-org/gitlab'

      MONTHLY_RELEASE_VERSION_REGEX = /\A(?<major>\d+)\.(?<minor>\d+)\z/

      MR_URL_REGEX = %r{https://gitlab.com/(?<project>.+)/-/merge_requests/(?<iid>\d+)}
      ALLOWED_MR_PROJECTS = [CANONICAL_PROJECT, SECURITY_PROJECT].freeze

      def initialize(merge_request_url, release_version, token)
        @mr_url = merge_request_url
        @version = release_version
        @token = token
      end

      def execute
        error = validate_args
        return response_message(error) if error

        result = check_tags_stable_branch_or_gprd

        response_message(result)
      end

      private

      attr_reader :mr_url, :version, :token

      def validate_args
        return :invalid_version_string unless version.nil? || MONTHLY_RELEASE_VERSION_REGEX.match?(version)

        validate_merge_request_url
      end

      def validate_merge_request_url
        return :invalid_mr_url unless mr_url_parts
        return :invalid_mr_project unless ALLOWED_MR_PROJECTS.include?(mr_project)
        return :mr_does_not_exist unless merge_request

        :mr_not_merged if merge_request.state != 'merged'
      end

      def check_tags_stable_branch_or_gprd
        if !lowest_tag.nil?
          :commit_already_released

        elsif version.nil?
          # Commit doesn't exist in any tag. And a version is not specified,
          # so we cannot check the stable branch.
          :commit_not_released

        elsif stable_branch.exists?
          check_commit_in_stable_branch

        else
          check_commit_deployed_to_gprd
        end
      end

      def check_commit_in_stable_branch
        if stable_branch.contains_commit?(merge_request.merge_commit_sha)
          :commit_present_in_stable_branch
        else
          :commit_not_present_in_stable_branch
        end
      end

      def check_commit_deployed_to_gprd
        commit_deployed_to_gprd =
          Gitlab::ReleaseCheck::Commit
            .new(production_client, SECURITY_PROJECT, merge_request.merge_commit_sha)
            .deployed_to_gprd?

        if commit_deployed_to_gprd
          :commit_deployed_to_gprd
        else
          :commit_not_deployed_to_gprd
        end
      end

      def stable_branch
        @stable_branch ||=
          Gitlab::ReleaseCheck::StableBranch.new(
            production_client,
            SECURITY_PROJECT,
            version
          )
      end

      def production_client
        @production_client ||= Gitlab::Client.new(token: token)
      end

      def merge_request
        @merge_request ||= production_client.merge_request(mr_project, mr_iid)
      rescue ::Gitlab::Error::NotFound
        nil
      end

      def mr_url_parts
        @mr_url_parts ||= MR_URL_REGEX.match(mr_url)
      end

      def mr_project
        mr_url_parts[:project]
      end

      def mr_iid
        mr_url_parts[:iid]
      end

      def lowest_tag
        @lowest_tag ||=
          Gitlab::ReleaseCheck::LowestTag
            .new(production_client, SECURITY_PROJECT, merge_request.merge_commit_sha)
            .execute
      end

      def slack_link(link, text)
        "<#{link}|#{text}>"
      end

      def mr_slack_link
        slack_link(mr_url, "#{mr_project}!#{mr_iid}")
      end

      def stable_branch_link
        slack_link("https://gitlab.com/#{SECURITY_PROJECT}/-/tree/#{stable_branch.name}", 'stable branch')
      end

      def tag_link(tag)
        slack_link("https://gitlab.com/#{SECURITY_PROJECT}/-/tree/#{tag}", tag)
      end

      def response_message(code)
        messages = {
          invalid_version_string:
            "'<%= version %>' is not a valid monthly release version. Monthly release versions " \
            'look like 10.0 or 14.2.',

          invalid_mr_url: '<%= mr_url %> is not a valid merge request URL.',

          invalid_mr_project: 'Only merge requests from <%= ALLOWED_MR_PROJECTS %> are currently supported.',

          mr_does_not_exist:
            '<%= mr_slack_link %> does not exist.',

          mr_not_merged: '<%= mr_slack_link %> has not been merged as yet!',

          commit_already_released: '<%= mr_slack_link %> was first released in <%= tag_link(lowest_tag) %>.',

          commit_not_released:
            '<%= mr_slack_link %> was not released in any past version. Try checking with the upcoming release ' \
            'version. Ex: `release check <MR URL> 14.2`',

          commit_present_in_stable_branch:
            '<%= mr_slack_link %> has been included in the <%= stable_branch_link %>. This MR ' \
            'will be released in <%= version %>.',

          commit_not_present_in_stable_branch:
            '<%= mr_slack_link %> has not been included in the <%= stable_branch_link %>. ' \
            'The MR _will not_ be released in <%= version %>.',

          commit_deployed_to_gprd:
            '<%= mr_slack_link %> has been deployed to gprd. It will most likely be ' \
            'included in release <%= version %>.',

          commit_not_deployed_to_gprd:
            '<%= mr_slack_link %> has not yet been deployed to gprd. It cannot be included ' \
            'in the monthly release until it is deployed to gprd.'
        }

        return ERB.new(messages[code]).result(binding) if messages.key?(code)

        raise "Did you forget to add a message string? The message string for '#{code}' is unknown."
      end
    end
  end
end
