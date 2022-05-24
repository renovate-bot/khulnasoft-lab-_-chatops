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
      def initialize(token:, host: DEFAULT_HOST, httparty: {})
        endpoint = "https://#{host}/api/v4"

        @host = host
        @internal_client = ::Gitlab::Client
          .new(endpoint: endpoint, private_token: token, httparty: httparty)
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

      # Update the extra shared runner minutes for a given namespace ID.
      def set_namespace_extra_minutes(namespace, minutes)
        body = { extra_shared_runners_minutes_limit: minutes }
        internal_client.put("/namespaces/#{namespace}", body: body)
      end

      # Sets a feature flag's state.
      #
      # name - The name of the flag.
      # value - The value to set for the flag.
      # project - A project actor
      # group - A group actor
      # user - A user actor
      # value - The value to set for the flag.
      # actors - Use a percentage of actors rollout
      def set_feature(name,
                      value,
                      project: nil,
                      group: nil,
                      user: nil,
                      namespace: nil,
                      actors: false)

        body = { value: value }

        body[:project] = project if project
        body[:group] = group if group
        body[:namespace] = namespace if namespace
        body[:user] = user if user
        body[:key] = 'percentage_of_actors' if actors

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
      def add_broadcast_message(message,
                                target_path:,
                                starts_at: nil,
                                ends_at: nil)
        body = { message: message, target_path: target_path }

        body[:starts_at] = starts_at if starts_at
        body[:ends_at] = ends_at if ends_at

        internal_client.post('/broadcast_messages', body: body)
      end

      def latest_deployments(project, environment, limit:, status: nil)
        options = {
          environment: environment,
          order_by: 'id',
          sort: 'desc',
          status: status
        }.compact

        internal_client
          .deployments(project, options)
          .paginate_with_limit(limit)
      end

      # Returns branches/tags containing the given commit SHA.
      #
      # @param project [Integer, String] the ID (`9970`) of the project or the full
      #   namespace path (`gitlab-org/gitlab`).
      # @param sha [String] the commit SHA.
      # @param type [String] the type of reference you want to check for. One of `tag`, `branch`, `all`.
      # @return [Array] Array of hashes, with each hash being a reference that contains the given SHA.
      def refs_containing_commit(project:, sha:, type: 'all')
        raise ArgumentError, 'Invalid `type` argument' unless %w[all branch tag].include?(type)

        internal_client
          .commit_refs(project, sha, type: type, per_page: 100)
          .auto_paginate
      rescue ::Gitlab::Error::NotFound
        []
      end

      def_delegator :internal_client, :block_user
      def_delegator :internal_client, :unblock_user
      def_delegator :internal_client, :edit_user
      def_delegator :internal_client, :emails
      def_delegator :internal_client, :delete_email

      def_delegator :internal_client, :run_trigger
      def_delegator :internal_client, :pipeline
      def_delegator :internal_client, :pipeline_jobs
      def_delegator :internal_client, :pipeline_schedules
      def_delegator :internal_client, :edit_pipeline_schedule
      def_delegator :internal_client, :pipelines

      def_delegator :internal_client, :add_group_member
      def_delegator :internal_client, :remove_group_member

      def_delegator :internal_client, :add_team_member,
                    :add_project_member
      def_delegator :internal_client, :remove_team_member,
                    :remove_project_member

      def_delegator :internal_client, :project, :find_project
      def_delegator :internal_client, :group, :find_group
      def_delegator :internal_client, :group_projects

      def_delegator :internal_client, :version
      def_delegator :internal_client, :commit
      def_delegator :internal_client, :commit_refs
      def_delegator :internal_client, :compare
      def_delegator :internal_client, :tree, :repository_tree
      def_delegator :internal_client, :tag

      def_delegator :internal_client, :create_issue
      def_delegator :internal_client, :close_issue
      def_delegator :internal_client, :issues

      def_delegator :internal_client, :create_branch
      def_delegator :internal_client, :create_merge_request
      def_delegator :internal_client, :create_file
      def_delegator :internal_client, :update_variable

      def_delegator :internal_client, :merge_request
      def_delegator :internal_client, :merge_requests

      def_delegator :internal_client, :branch
    end
  end
end
