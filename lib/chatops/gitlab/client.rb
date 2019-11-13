# frozen_string_literal: true

module Chatops
  module Gitlab
    # HTTP client for the GitLab API.
    class Client
      extend Forwardable

      DEFAULT_HOST = 'gitlab.com'

      attr_reader :internal_client, :host

      # token - The API token to use for authentication.
      # host - The hostname to use.
      def initialize(token:, host: DEFAULT_HOST)
        endpoint = "https://#{host}/api/v4"

        @host = host
        @internal_client = ::Gitlab::Client
          .new(endpoint: endpoint, private_token: token)
      end

      def features
        internal_client.get('/features').auto_paginate
      end

      # Returns a user for a given username or email address.
      def find_user(username_or_email)
        if /[^@]+@[^\.]+\..+/.match?(username_or_email)
          internal_client.users(search: username_or_email).first
        else
          internal_client.users(username: username_or_email).first
        end
      end

      # Returns a namespace for a given namespace ID.
      def find_namespace(namespace)
        internal_client.get("/namespaces/#{namespace}")
      end

      # Return a list of objects from a project.
      def repository_tree(project_id, options = {})
        internal_client.tree(project_id, options)
      end

      # Sets a feature flag's state.
      #
      # name - The name of the flag.
      # value - The value to set for the flag.
      def set_feature(name, value, project: nil, group: nil, user: nil)
        body = { value: value }

        body[:project] = project if project
        body[:group] = group if group
        body[:user] = user if user

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

      def_delegator :internal_client, :block_user
      def_delegator :internal_client, :unblock_user

      def_delegator :internal_client, :run_trigger
      def_delegator :internal_client, :pipeline_jobs

      def_delegator :internal_client, :add_group_member
      def_delegator :internal_client, :remove_group_member

      def_delegator :internal_client, :add_team_member,
                    :add_project_member
      def_delegator :internal_client, :remove_team_member,
                    :remove_project_member

      def_delegator :internal_client, :project, :find_project
      def_delegator :internal_client, :group, :find_group

      def_delegator :internal_client, :version
      def_delegator :internal_client, :commit

      def_delegator :internal_client, :create_issue
      def_delegator :internal_client, :close_issue

      def commit_refs(project, sha, options = {})
        path = internal_client.url_encode(project)

        # NOTE: The GitLab gem doesn't currently support this API
        # See https://github.com/NARKOZ/gitlab/pull/507
        internal_client.get(
          "/projects/#{path}/repository/commits/#{sha}/refs",
          query: options
        )
      end
    end
  end
end
