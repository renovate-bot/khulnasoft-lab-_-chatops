# frozen_string_literal: true

module Chatops
  module PagerDuty
    class User
      PRIMARY_ONCALL_LEVEL = 1

      attr_reader :name, :email, :avatar_url, :escalation_level

      def initialize(policy)
        @name = policy['user']['name']
        @email = policy['user']['email']
        @avatar_url = policy['user']['avatar_url']

        @escalation_level = policy['escalation_level']
      end

      def escalation_title
        if escalation_level == PRIMARY_ONCALL_LEVEL
          'Primary Oncall'
        else
          'Escalation Manager'
        end
      end

      def escalation_color
        if escalation_level == PRIMARY_ONCALL_LEVEL
          'good'
        else
          'warning'
        end
      end
    end
  end
end
