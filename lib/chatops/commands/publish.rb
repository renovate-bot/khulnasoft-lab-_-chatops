# frozen_string_literal: true

module Chatops
  module Commands
    class Publish
      include Command

      description 'Add a short description of the command here.'

      # The "options" method can be used to add additional options (e.g. a
      # --version option). For more information see
      # https://github.com/leejarvis/slop/#usage.
      #
      # If your command does not use any options you should just remove this
      # comment and the block that follows it.
      options do |o|
      end

      def perform
        # This method is called when the command is executed. If this method
        # returns a non-nil value it will be used as the command output
        # (which in turn is sent back to the user).
      end
    end
  end
end