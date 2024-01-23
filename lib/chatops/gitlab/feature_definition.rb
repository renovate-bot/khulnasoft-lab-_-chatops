# frozen_string_literal: true

module Chatops
  module Gitlab
    # Class for retrieving feature flag definition from its YAML definition file.
    class FeatureDefinition
      include GitlabEnvironments
      include ::SemanticLogger::Loggable

      MONOLITH_PROJECT = 'gitlab-org/gitlab'
      ISSUE_REGEXP = %r{gitlab\.com/(?<issue_project_path>.+)/-/issues/(?<issue_iid>\d+)}

      attr_reader :name

      # name - The name of the feature flag.
      def initialize(name:, env: {})
        @name = name
        @env = env
        @options = {}
      end

      def introduced_by_url
        definition[:introduced_by_url]
      end

      def rollout_issue_url
        definition[:rollout_issue_url]
      end

      def milestone
        definition[:milestone]
      end

      def type
        definition[:type]
      end

      def group_label
        definition[:group]
      end

      def default_enabled
        definition[:default_enabled]
      end

      def rollout_issue_project_path
        return unless rollout_issue_url

        matches = rollout_issue_url.match(ISSUE_REGEXP)
        return unless matches

        matches[:issue_project_path]
      end

      def rollout_issue_iid
        return unless rollout_issue_url

        matches = rollout_issue_url.match(ISSUE_REGEXP)
        return unless matches

        matches[:issue_iid]
      end

      private

      attr_reader :env, :options

      def production_api_client
        @production_api_client ||= environment.api_client
      end

      def definition
        @definition ||= fetch_definition
      end

      def fetch_definition
        pattern = "#{name} file:^(config/feature_flags/|ee/config/feature_flags/)"
        search_results = production_api_client.search_in_project(MONOLITH_PROJECT, 'blobs', pattern)

        if search_results.any?
          logger.info(
            "Found #{search_results.size} files matching `#{pattern}`." \
            " `#{search_results.first['path']}` will be fetched."
          )

          file_content = production_api_client.file_contents(
            project: MONOLITH_PROJECT,
            path: search_results.first['path']
          )

          if file_content
            return YAML.safe_load(
              file_content,
              permitted_classes: [Symbol],
              symbolize_names: true
            )
          else
            logger.info("Feature flag definition `#{search_results.first['path']}` returned 404!")
          end
        else
          logger.info("Found no files matching `#{pattern}`!")
        end

        {} # fallback to an empty hash
      rescue ::Gitlab::Error::InternalServerError => ex
        logger.info("The search for the `#{name}` flag definition file returned 500:\n#{ex.message}")
        {} # fallback to an empty hash
      end
    end
  end
end
