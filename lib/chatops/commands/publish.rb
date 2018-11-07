# frozen_string_literal: true

module Chatops
  module Commands
    # Triggers a pipeline in release-tools that publishes packages for a
    # specified version.
    #
    # See https://gitlab.com/gitlab-org/release-tools/blob/master/doc/chatops.md#publish
    class Publish
      include Command
      include Release::Command

      usage "#{command_name} [VERSION]"
      description 'Publish packages for a specified version.'

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        trigger_release(version)
      end
    end
  end
end
