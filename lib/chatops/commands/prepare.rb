# frozen_string_literal: true

module Chatops
  module Commands
    class Prepare
      include Command
      include Release::Command

      usage "#{command_name} [VERSION]"
      description 'Create preparation merge requests.'

      def perform
        version = required_argument(0, 'version')
        validate_version!(version)

        trigger_release(version, 'patch_merge_request')
      end
    end
  end
end
