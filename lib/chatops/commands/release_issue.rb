# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in release-tools that creates a release task issue for
    # a specified version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/chatops.md#release-issues
    class ReleaseIssue
      include Command
      include Release::Command

      usage "#{command_name} [VERSION]"
      description 'Create a task issue for a specified version.'

      options do |o|
        o.bool '--security', 'Create a security release issue', default: false
      end

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        if options[:security]
          task = 'security_patch_issue'
        else
          matches = version.match(VERSION_REGEX)

          task =
            if matches[:patch].to_i.zero? && matches[:rc].nil?
              'monthly_issue'
            else
              'patch_issue'
            end
        end

        trigger_release(version, task)
      end
    end
  end
end
