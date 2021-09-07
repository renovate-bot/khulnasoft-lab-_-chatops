# frozen_string_literal: true

module Chatops
  module Gitlab
    class Deployments
      def initialize(client, project)
        @client = client
        @project = project
      end

      # Get the latest successful and running (if available) deployments for a
      # given environment
      #
      # Returns an Array of Deployment instances
      def upcoming_and_current(environment)
        latest = @client
          .latest_deployments(@project, environment, limit: 10)
          .map { |d| Deployment.new(d) }

        # Remove failed deploys
        latest.reject!(&:failed?)

        # Now we only need the latest two
        latest = latest.take(2)

        # Two successful deploys means nothing is upcoming; return only current
        latest.pop if latest.length == 2 && latest.all?(&:success?)

        latest
      end
    end
  end
end
