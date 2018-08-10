# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in release-tools that tags a specified version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/chatops.md#tag
    class Tag
      include Command
      include Release::Command

      VERSION_REGEX = /\A\d+\.\d+\.\d+(-rc\d+)?\z/

      usage "#{command_name} [VERSION]"
      description 'Tag a new version of GitLab.'

      options do |o|
        o.bool '--security', 'Tag a security release', default: false
      end

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        task_name = self.class.command_name.dup
        task_name << '_security' if options[:security]

        trigger_release(version, task_name)
      end

      private

      def validate_version!(version)
        return if VERSION_REGEX.match?(version)

        raise ArgumentError, "Invalid version provided: #{version}"
      end
    end
  end
end
