# frozen_string_literal: true

module Chatops
  module Gitlab
    class Project
      def initialize(project, client)
        @project = project
        @client = client
      end

      def id
        @project.id
      end

      def add_user(user, access_level = nil)
        @client.add_project_member(id, user.id, access_level)
      end

      def remove_user(user)
        @client.remove_project_member(id, user.id)
      end
    end
  end
end
