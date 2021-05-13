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
          .latest_deployments(@project, environment, limit: 2)
          .map { |d| Deployment.new(d) }

        # Two successful deploys means nothing is running; return only latest
        latest.pop if latest.all?(&:success?)

        # Remove the latest deploy if it failed
        latest.reject!(&:failed?)

        latest
      end
    end
  end
end
