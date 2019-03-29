# frozen_string_literal: true

module Chatops
  module Gitlab
    # HTTP client for the GitLab API.
    class Client
      DEFAULT_ENDPOINT = 'https://gitlab.com/api/v4'

      attr_reader :internal_client

      # token - The API token to use for authentication.
      # host - The hostname to use.
      def initialize(token:, host: nil)
        endpoint = host ? "https://#{host}/api/v4" : DEFAULT_ENDPOINT

        @internal_client = ::Gitlab::Client
          .new(endpoint: endpoint, private_token: token)
      end

      def features
        internal_client.get('/features').auto_paginate
      end

      # Returns a user for a given username.
      def find_user(username)
        internal_client.users(username: username).first
      end

      # Returns a namespace for a given namespace ID.
      def find_namespace(namespace_id)
        internal_client.namespaces(search: namespace_id)
      end

      # Sets a feature flag's state.
      #
      # name - The name of the flag.
      # value - The value to set for the flag.
      def set_feature(name, value, project: nil, group: nil)
        body = { value: value }

        body[:project] = project if project
        body[:group] = group if group

        internal_client.post("/features/#{name}", body: body)
      end

      # Delete a feature flag
      #
      # name = The name of the flag.
      def delete_feature(name)
        internal_client.delete("/features/#{name}")
      end

      # Adds a broadcast message.
      #
      # message - The message to add.
      # starts_at - The start time of the message.
      # ends_at - The stop time of the message.
      def add_broadcast_message(message, starts_at: nil, ends_at: nil)
        body = { message: message }

        body[:starts_at] = starts_at if starts_at
        body[:ends_at] = ends_at if ends_at

        internal_client.post('/broadcast_messages', body: body)
      end

      # id - The ID of the user to block.
      def block_user(id)
        internal_client.block_user(id)
      end

      # id - The ID of the user to unblock.
      def unblock_user(id)
        internal_client.unblock_user(id)
      end

      def run_trigger(project, token, ref, options = {})
        internal_client.run_trigger(project, token, ref, options)
      end

      def pipeline_jobs(project, pipeline_id, options = {})
        internal_client.pipeline_jobs(project, pipeline_id, options)
      end

      def add_group_member(group, user, access_level)
        internal_client.add_group_member(group, user, access_level)
      end

      def add_project_member(project, user, access_level)
        internal_client.add_team_member(project, user, access_level)
      end

      def remove_group_member(group, user)
        internal_client.remove_group_member(group, user)
      end

      def remove_project_member(project, user)
        internal_client.remove_team_member(project, user)
      end

      def find_project(name)
        internal_client.project(name)
      end

      def find_group(name)
        internal_client.group(name)
      end
    end
  end
end
