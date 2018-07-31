# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in release-tools that creates a release task issue for
    # a specified version.
    #
    # This command is context-aware and will create a specific type of task
    # issue based on where the command was run:
    #
    # - In #security, it will create a security task issue
    # - Anywhere else, it will create either a monthly issue or a patch issue,
    #   depending on the version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/chatops.md#release-issues
    class ReleaseIssue
      include Command
      include Release::Command

      VERSION_REGEX = /\A\d+\.\d+\.(?<patch>\d+)(-rc(?<rc>\d+))?\z/
      SECURITY_CHANNEL = 'CBTF82B1C' # security-release

      usage "#{command_name} [VERSION]"
      description 'Create a task issue for a specified version.'

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        if channel == SECURITY_CHANNEL
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

      private

      def validate_version!(version)
        return if VERSION_REGEX.match?(version)

        raise ArgumentError, "Invalid version provided: #{version}"
      end

      def channel
        super
      rescue KeyError
        # Some tests don't provide the channel environment variable. That's ok.
        'releases'
      end
    end
  end
end
