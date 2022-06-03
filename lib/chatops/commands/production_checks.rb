# frozen_string_literal: true

module Chatops
  module Commands
    class ProductionChecks
      include Command
      include ::Chatops::Release::Command

      description 'Performs a production check and displays the result'

      def perform
        run_trigger(CHECK_PRODUCTION: 'true', PRODUCTION_CHECK_SCOPE: 'deployment')

        'Production checks triggered, the results will appear shortly.'
      end
    end
  end
end
