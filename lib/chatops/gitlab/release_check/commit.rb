# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class Commit
        AUTO_DEPLOY_BRANCH_REGEX = /^\d+-\d+-auto-deploy-\d+$/

        def initialize(client, project, commit_sha)
          @client = client
          @project = project
          @sha = commit_sha
        end

        # Returns true if the commit has been deployed to gprd.
        #
        # @return [Boolean]
        def deployed_to_gprd?
          branches_containing_sha = auto_deploy_branches_containing_commit(sha)

          gprd_environment_status.any? do |environment|
            branches_containing_sha.any? do |auto_deploy_branch|
              environment[:branch] == auto_deploy_branch.name && environment[:status] == 'success'
            end
          end
        end

        private

        attr_reader :client, :project, :sha

        def gprd_environment_status
          rails = Gitlab::Deployments
            .new(client, project)
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

        def auto_deploy_branches_containing_commit(sha)
          client
            .refs_containing_commit(project: project, type: 'branch', sha: sha)
            .select { |b| b.name.match?(AUTO_DEPLOY_BRANCH_REGEX) }
        end
      end
    end
  end
end
