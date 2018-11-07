# frozen_string_literal: true

module Chatops
  module Gitlab
    class Group
      def initialize(group, client)
        @group = group
        @client = client
      end

      def id
        @group.id
      end

      def add_user(user, access_level = nil)
        @client.add_group_member(id, user.id, access_level)
      end

      def remove_user(user)
        @client.remove_group_member(id, user.id)
      end
    end
  end
end
