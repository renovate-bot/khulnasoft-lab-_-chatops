# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class Projects
        GITLAB_SECURITY_PROJECT = 'gitlab-org/security/gitlab'
        GITLAB_CANONICAL_PROJECT = 'gitlab-org/gitlab'

        OMNIBUS_SECURITY_PROJECT = 'gitlab-org/security/omnibus-gitlab'
        OMNIBUS_CANONICAL_PROJECT = 'gitlab-org/omnibus-gitlab'
      end
    end
  end
end
