# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class Commit
        # 14-8-auto-deploy-2022020906
        GITLAB_AUTO_DEPLOY_BRANCH_REGEX = /^\d+-\d+-auto-deploy-\d+$/

        # 14.8.202202082218+113b5654b3c.d8c9987d59d
        OMNIBUS_AUTO_DEPLOY_TAG_REGEX = /^\d+\.\d+\.\d+\+\h+\.\h+$/

        def initialize(client, project, commit_sha)
          @client = client
          @project = project
          @sha = commit_sha
        end

        # Returns true if the commit has been deployed to gprd.
        #
        # @return [Boolean]
        def deployed_to_gprd?
          refs_containing_sha = auto_deploy_refs_containing_commit(sha)

          gprd_environment_status.any? do |environment|
            refs_containing_sha.any? do |auto_deploy_ref|
              environment[:branch] == auto_deploy_ref.name && environment[:status] == 'success'
            end
          end
        end

        private

        attr_reader :client, :project, :sha

        def gprd_environment_status
          deployments = Gitlab::Deployments
            .new(client, project)
            .upcoming_and_current('gprd')

          deployments.map do |ee|
            {
              role: 'gprd',
              revision: (ee&.short_sha || 'unknown'),
              branch: (ee&.ref || 'unknown'),
              status: (ee&.status || 'unknown')
            }
          end
        end

        def auto_deploy_refs_containing_commit(sha)
          client
            .refs_containing_commit(project: project, type: ref_type, sha: sha)
            .select { |ref| ref.name.match?(auto_deploy_regex) }
        end

        def auto_deploy_regex
          @auto_deploy_regex ||=
            if Projects::GITLAB_SECURITY_PROJECT == project
              GITLAB_AUTO_DEPLOY_BRANCH_REGEX
            elsif Projects::OMNIBUS_SECURITY_PROJECT == project
              OMNIBUS_AUTO_DEPLOY_TAG_REGEX
            end
        end

        def ref_type
          @ref_type ||=
            if Projects::GITLAB_SECURITY_PROJECT == project
              'branch'
            elsif Projects::OMNIBUS_SECURITY_PROJECT == project
              'tag'
            end
        end
      end
    end
  end
end
