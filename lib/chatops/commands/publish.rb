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

      options do |o|
        o.bool '--security', 'Act as a security release', default: false
      end

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        if options[:security]
          trigger_release(version, 'security:publish')
        else
          trigger_release(version)
        end
      end
    end
  end
end
