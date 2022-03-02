# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class Projects
        GITLAB_SECURITY = 'gitlab-org/security/gitlab'
        GITLAB_CANONICAL = 'gitlab-org/gitlab'

        OMNIBUS_SECURITY = 'gitlab-org/security/omnibus-gitlab'
        OMNIBUS_CANONICAL = 'gitlab-org/omnibus-gitlab'

        def self.security_project_for(project)
          case project

          when GITLAB_CANONICAL, GITLAB_SECURITY
            GITLAB_SECURITY

          when OMNIBUS_CANONICAL, OMNIBUS_SECURITY
            OMNIBUS_SECURITY
          end
        end
      end
    end
  end
end
