# frozen_string_literal: true

module Chatops
  module Commands
    class Feature
      include Command
      include GitlabEnvironments
      include ::Chatops::Release::Command
      include ::SemanticLogger::Loggable

      ProductionCheckTimeout = Class.new(StandardError)
      PRODUCTION_SLACK_CHANNEL_ID = 'C101F3796'
      PRODUCTION_CHECK_DURATION = 300
      PRODUCTION_CHECK_INTERVAL = 2

      # The color to use for the attachment containing enabled features.
      ENABLED_COLOR = '#B3ED8E'

      # The color to use for the attachment containing disabled features.
      DISABLED_COLOR = '#ccc'

      # All the available subcommands and the corresponding methods to invoke.
      COMMANDS = Set.new(%w[get set list delete])

      # The URL to the Gates documentation, to be displayed when retrieving a
      # single feature.
      GATES_DOCUMENTATION = 'https://www.flippercloud.io/docs/features'

      # The project name to use for logging the toggling of feature flags.
      LOG_PROJECT = 'gitlab-com/gl-infra/feature-flag-log'

      # The project used for recording ongoing production incidents.
      INCIDENTS_PROJECT = 'gitlab-com/gl-infra/production'

      # The severity labels applied to an incident issue before it blocks
      # changing feature flags.
      SEVERITY_LABELS = %w[severity::1 severity::2].freeze

      # IDs of QA channels to send message each time a feature flag is set
      QA_CHANNELS = {
        STAGING_HOST => 'CBS3YKMGD',       # `#qa-staging`
        STAGING_REF_HOST => 'C02JGFF2EAZ', # `#qa-staging-ref`
        PRODUCTION_HOST => 'CCNNKFP8B',    # `#qa-production`
        PRE_HOST => 'CR7QH0RV1'            # `#qa-preprod`
      }.freeze

      RESPONSES = {
        production_ff_requires_production_channel:
          'Unable to proceed because a production feature flag change ' \
          'may only be invoked in the #production Slack channel.'
      }.freeze

      # This job name is defined in release-tools.
      # https://gitlab.com/gitlab-org/release-tools/-/blob/9358665fa14fd92b4296b11cb1fda88f97d27580/.gitlab/ci/auto-deploy.gitlab-ci.yml#L39
      AUTO_DEPLOY_CHECK_PRODUCTION_JOB = 'auto_deploy:check_production'

      MONOLITH_PROJECT = 'gitlab-org/gitlab'
      ISSUE_REGEXP = %r{gitlab\.com/(?<issue_project_path>.+)/-/issues/(?<issue_iid>\d+)}

      ISSUE_HEADER = <<~DESC
        * Changed by [`@%<username>s`](https://gitlab.com/%<username>s) at `%<now>s` (UTC)
        * Host: %<environment_host>s
        * Rollout issue: %<rollout_issue_url>s
      DESC
      ISSUE_SCOPES_TABLE = <<~MARKDOWN
        ## Feature flag scopes

        This feature flag applies the following scopes (if any):

        | User                     | Project                     | Group                     | Feature group                     | Namespace                     | Repository                     |
        |--------------------------|-----------------------------|---------------------------|-----------------------------------|-------------------------------|--------------------------------|
        | `%<feature_scope_user>s` | `%<feature_scope_project>s` | `%<feature_scope_group>s` | `%<feature_scope_feature_group>s` | `%<feature_scope_namespace>s` | `%<feature_scope_repository>s` |

        When a value is empty, it means the scope does not apply. If none of these scopes are set it means the feature flag applies globally.
      MARKDOWN
      ISSUE_FOOTER = <<~MARKDOWN
        <hr>

        :robot: This issue was generated using [GitLab Chatops](https://gitlab.com/gitlab-com/chatops/).
      MARKDOWN

      description 'Managing of GitLab feature flags.'
      enable_multi_environments

      # rubocop: disable Metrics/BlockLength
      options do |o|
        o.string(
          '--match',
          'Only displays features that contain the given substring'
        )
        o.string(
          '--project',
          "The path of a project to set a feature flag for, e.g. \
          gitlab-org/gitaly"
        )
        o.string(
          '--group',
          'The path of a group to set a feature flag for, e.g. gitlab-org'
        )
        o.string(
          '--feature-group',
          'The name of a feature group to set a feature flag, e.g. gitlab_team_members'
        )
        o.string(
          '--namespace',
          'The path of a group or user namespace to set a feature flag for, e.g. gitlab-org'
        )
        o.string(
          '--user',
          'The username of a user to set a feature flag for, e.g. someuser'
        )
        o.string(
          '--repository',
          'The fullpath of a repository to set a feature flag for, e.g. gitlab-org/gitlab.git. This is essentially ' \
          'the path to clone that repository. This actor is typically used when passing the flags to Gitaly.'
        )
        o.bool('--actors',
               'Modifier to roll out a feature flag to a percentage of actors')

        o.bool('--random',
               'Modifier to roll out a feature flag to a percentage of time (deprecated)')

        o.boolean(
          '--ignore-production-check',
          "Ignore the production check when changing a feature flag's state"
        )

        o.bool(
          '--ignore-random-deprecation-check',
          'Allow usage of the deprecated option --random'
        )

        o.boolean(
          '--ignore-feature-flag-consistency-check',
          "Ignore the feature flag consistency check when changing a feature flag's state"
        )

        GitlabEnvironments.define_environment_options(o)

        o.separator("\nAvailable subcommands:\n\n#{available_subcommands}")
      end
      # rubocop: enable Metrics/BlockLength

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The feature subcommand is invalid. The following subcommands are available:

          #{list}

          Some examples:

          ```
          # Listing all features:
          feature list

          # Listing all features with a name that contains "gitaly":
          feature list --match gitaly

          # To obtain details of a single feature:
          feature get gitaly_tags

          # To always enable a feature:
          feature set gitaly_tags true

          # [Deprecated in favor of using actors] To enable a feature 50% of the time:
          feature set gitaly_tags 50 --random --ignore-random-deprecation-check

          # To enable a feature 50% of the actors:
          feature set gitaly_tags 50 --actors

          # To enable a feature for a project
          feature set --project=gitlab-org/gitaly gitaly_tags

          # To enable a feature for a group
          feature set --group=gitlab-org gitaly_tags

          # To enable a feature for all team members (for flags scoped to a user)
          feature set --feature-group=gitlab_team_members gitaly_tags

          # To enable a feature for a namespace
          feature set --namespace=gitlab-org gitaly_tags # Same as `feature set --group=gitlab-org gitaly_tags`
          feature set --namespace=someuser gitaly_tags

          # To enable a feature for a user
          feature set --user=someuser gitaly_tags

          # To enable a feature for a repository
          feature set --repository=snippets/2427310.git gitaly_tags
          feature set --repository=gitlab-org.wiki.git gitaly_tags

          # To delete a feature flag and return to default behaviour:
          feature delete gitaly_tags
          ```

          For more information run `feature --help`.
        MESSAGE
      end

      # Retrieves details of a single feature flag.
      def get
        errors = []

        environments.each do |environment|
          if (error = get_on(environment))
            errors << error
          end
        end

        errors.join("\n") unless errors.empty?
      end

      def get_on(environment)
        unless feature_name
          return 'You must specify the name of the feature. ' \
            'For example: `feature get gitaly_tags`'
        end

        feature = get_feature(feature_name, environment)

        return "The feature #{feature_name.inspect} does not exist on #{environment.env_name}." unless feature

        send_feature_details(feature: feature, environment: environment)
      end

      def get_feature(name, environment)
        Gitlab::FeatureCollection
          .new(token: environment.gitlab_token, host: environment.gitlab_host)
          .find_by_name(name)
      end

      # rubocop: disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
      # Updates the value of a single feature flag.
      def set
        errors = []

        environments.each do |environment|
          if (error = set_on(environment))
            errors << error
          end
        end

        errors.join("\n") unless errors.empty?
      end

      # rubocop:disable Naming/AccessorMethodName
      def set_on(environment)
        prod_check_failure_resp =
          'Unable to proceed due to production check failure. ' \
          'If you absolutely must change ' \
          'the state of this feature flag, ' \
          'please confirm with the current SRE ' \
          'oncall `@sre-oncall`, and use the ' \
          '--ignore-production-check option.'

        feature_flag_consistency_check_failure_resp =
          'Unable to proceed due to inconsistent feature flag status. ' \
          'When the flag on production is turned on, staging should be on too. ' \
          'If you absolutely must change ' \
          'the state of this feature flag, ' \
          'please confirm with the current SRE ' \
          'oncall `@sre-oncall`, and use the ' \
          '--ignore-feature-flag-consistency-check. '

        value = arguments[2]

        if !feature_name || !value
          return 'You must specify the name of the feature flag ' \
            'and its new value.'
        end

        unless Gitlab::Feature.valid_value?(value)
          return "The value #{value.inspect} is invalid. " \
            'Valid values are: `true`, `false`, or an integer from 0 to 100.'
        end

        return 'One of `--actors` or `--random` must be set for percentage values.' \
          unless valid_setting_for_percentage_value?(value, options)

        unless valid_actors_random_setting?(options)
          return '`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, ' \
            '`--namespace`, `--user`, or `--repository`.'
        end

        if random_not_forced?(options)
          return 'Time percentage feature flags are being deprecated in favor of using actors. If you understand ' \
            'the consequences, you can force it using --ignore-random-deprecation-check'
        end

        return wrong_channel_resp if environment.production? && channel != production_channel_id
        return prod_check_failure_resp unless production_check?(environment)
        return feature_flag_consistency_check_failure_resp unless feature_flag_consistency_check?(value, environment)

        response = environment.api_client
          .set_feature(feature_name, value, project: options[:project],
                                            group: options[:group],
                                            feature_group: options[:feature_group],
                                            namespace: options[:namespace],
                                            user: options[:user],
                                            repository: options[:repository],
                                            actors: options[:actors])

        feature = Gitlab::Feature.from_api_response(response)
        perform_side_effects(feature_name, value, feature, environment, options)
      rescue ProductionCheckTimeout => e
        e.message + ' ' + check_failure_resp
      end
      # rubocop: enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

      def wrong_channel_resp
        RESPONSES[:production_ff_requires_production_channel]
      end

      def production_check?(environment)
        return true unless environment.production?
        return true if options[:ignore_production_check]

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: {
            text: 'Production check initiated, this may take up to ' \
              "#{PRODUCTION_CHECK_DURATION} seconds ..."
          }
        )

        start = Time.now.to_i
        resp = run_trigger(
          CHECK_PRODUCTION: 'true',
          FAIL_IF_NOT_SAFE: 'true',
          SKIP_DEPLOYMENT_CHECK: 'true',
          PRODUCTION_CHECK_SCOPE: 'feature_flag'
        )

        loop do
          case production_check_status(resp.id)
          when PIPELINE_SUCCESS
            return true
          when PIPELINE_FAILED
            return false
          end

          if Time.now.to_i > (start + PRODUCTION_CHECK_DURATION)
            raise(
              ProductionCheckTimeout,
              'Timed out waiting for a response for ' \
              "<#{resp.web_url}|production check>. " \
              'If the check passes past the timeout, ' \
              'you can retry and use the override option.'
            )
          end

          sleep(PRODUCTION_CHECK_INTERVAL)
        end
      end
      # rubocop:enable Naming/AccessorMethodName

      def feature_flag_consistency_check?(value, environment)
        return true if options[:ignore_feature_flag_consistency_check]

        if environment.staging? && disable_feature_value?(value)
          prod_options = options.dup
          prod_options.delete(:staging)

          # If production is enabled, we should not turn it off for staging
          !feature_enabled_with_opts?(prod_options, Environment.production)
        elsif environment.production? && enable_feature_value?(value)
          staging_opts = options.dup
          staging_opts[:staging] = true

          # If staging is disabled, we shouldn't turn on for production
          feature_enabled_with_opts?(staging_opts, Environment.staging)
        else
          true
        end
      end

      def perform_side_effects(name, value, feature, environment, options)
        annotate_feature_toggle(name, value, environment)
        send_feature_toggle_event(name, value, environment, options)
        issue = log_feature_toggle(name, value, environment)
        notify_and_link_rollout_issue(name, issue)

        output = []
        output << send_feature_details(
          feature: feature,
          text: 'The feature flag value has been updated!',
          environment: environment
        )

        trigger_tests_response = Chatops::Gitlab::TestsPipeline.new(environment.env_name, options, name, value)
          .trigger_end_to_end

        output << send_feature_toggling_to_qa_channel(issue, environment, trigger_tests_response)

        output.compact.join("\n")
      end

      # Lists all the available feature flags per state.
      def list
        environments.each do |environment|
          list_on(environment)
        end

        nil
      end

      def list_on(environment)
        enabled, disabled = attachment_fields_per_state(environment)

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: {
            attachments: [
              {
                title: 'Enabled Features',
                text: 'These features are enabled:',
                fields: enabled,
                color: ENABLED_COLOR,
                footer: "#{enabled.length} enabled features on #{environment.gitlab_host}"
              },
              {
                title: 'Disabled Features',
                text: 'These features are disabled:',
                fields: disabled,
                color: DISABLED_COLOR,
                footer: "#{disabled.length} disabled features on #{environment.gitlab_host}"
              }
            ]
          }
        )
      end

      # Remove a feature flag
      #
      # Idempotent request, deleting non existing flags seems successful
      def delete
        environments.each do |environment|
          delete_on(environment)
        end

        nil
      end

      def delete_on(environment)
        return wrong_channel_resp if environment.production? && channel != production_channel_id

        environment.api_client.delete_feature(feature_name)

        send_feature_toggle_event(feature_name, 'deleted', environment)
        log_feature_toggle(feature_name, 'deleted', environment)

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: {
            text: "Feature flag #{feature_name} has been removed from #{environment.gitlab_host}!"
          }
        )
      end

      # Sends the details of a single feature back to Slack.
      #
      # feature - A `Chatops::Gitlab::Feature` instance containing the details
      #           we want to send back.
      # text - Optional text to include in the message.
      def send_feature_details(feature:, text: nil, environment:)
        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: {
            text: text,
            attachments: [
              {
                title: 'Feature',
                fields: [
                  {
                    title: 'Name',
                    value: feature.name,
                    short: true
                  },
                  {
                    title: 'State',
                    value: feature.state_label,
                    short: true
                  },
                  *feature.attachment_fields_for_gates
                ],
                footer: "Host: #{environment.gitlab_host}"
              }
            ]
          }
        )
      end

      def send_feature_toggling_to_qa_channel(issue, environment, trigger_tests_response = nil)
        channel = QA_CHANNELS[environment.gitlab_host]
        return unless channel

        blocks = [{
          type: 'section',
          text: Slack.markdown(text_for_slack_message(trigger_tests_response, issue))
        }]

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: { blocks: blocks }
        )
      end

      def text_for_slack_message(trigger_tests_response, issue)
        if trigger_tests_response
          body = if trigger_tests_response.include?('Failed')
                   trigger_tests_response
                 else
                   "An end-to-end test pipeline has been triggered: #{trigger_tests_response}"
                 end
        end

        <<~DESC
          <#{issue.web_url}|#{issue.title}>

          #{body}
        DESC
      end

      def send_slack_message_safely(slack_token:, channel:, slack_args:)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(**slack_args)
      rescue Slack::Message::MessageError => error
        'The following Slack message could not be posted to channel ' \
        "'#{channel}': #{slack_args}\n\nError: #{error.message}"
      end

      def attachment_fields_per_state(environment)
        Gitlab::FeatureCollection
          .new(token: environment.gitlab_token, match: options[:match], host: environment.gitlab_host)
          .per_state
          .map { |vals| vals.map(&:to_attachment_field) }
      end

      def send_feature_toggle_event(name, value, environment, options = {})
        return unless environment.staging? || environment.staging_ref? || environment.production?

        scopes = event_scopes_hash(options).merge(feature_scope_actors: options[:actors]&.to_s).compact

        Chatops::Events::Client
          .new(environment.env_name)
          .send_event(
            log_title(name, value, environment, options),
            fields: {
              feature_name: name,
              feature_value: value.to_s
            }.merge(scopes)
          )
      end

      def log_feature_toggle(name, value, environment)
        host = environment.gitlab_host
        labels = "host::#{host}, change"

        description = issue_description(name, value, environment, options)

        if options[:ignore_production_check]
          labels += ', Production check ignored'

          description = ':warning: **This feature flag was changed despite ' \
            'the production checks failing**' \
            "\n\n#{description}"
        end

        production_api_client.create_issue(
          LOG_PROJECT,
          log_title(name, value, environment, options),
          labels: labels,
          description: description
        ).tap do |issue|
          production_api_client.close_issue(issue.project_id, issue.iid)
        end
      end

      private

      def notify_and_link_rollout_issue(feature_flag_name, log_issue)
        project = rollout_issue_project_path(feature_flag_name)
        issue_iid = rollout_issue_iid(feature_flag_name)

        production_api_client.create_issue_note(
          project,
          issue_iid,
          "#{log_issue.title}. Feature flag state change log issue: #{log_issue.web_url}"
        )

        production_api_client.create_issue_link(
          project,
          issue_iid,
          log_issue.project_id,
          log_issue.iid
        )
      end

      def annotate_feature_toggle(name, value, environment)
        Grafana::Annotate.new(token: grafana_token)
          .annotate!(
            "#{username} set feature flag #{name} to #{value}",
            tags: [environment.env_name, 'feature-flag', name]
          )
      end

      def username
        @username ||= env.fetch('GITLAB_USER_LOGIN')
      end

      def production_channel_id
        ENV.fetch('PRODUCTION_SLACK_CHANNEL_ID', PRODUCTION_SLACK_CHANNEL_ID)
      end

      def flag_was_deleted?(value)
        value == 'deleted'
      end

      def log_title(name, value, environment, options)
        value = final_value(value, options)

        title = ["Feature flag '#{name}'"]
        title <<
          if flag_was_deleted?(value)
            'has been deleted'
          else
            "has been set to '#{value}'"
          end
        title << 'of actors' if options[:actors]
        title << "on #{environment.env_name}"

        title.join(' ')
      end

      def final_value(value, options)
        return "#{value}%" if options[:actors]

        value
      end

      def event_scopes_hash(options)
        {
          feature_scope_user: options[:user],
          feature_scope_project: options[:project],
          feature_scope_group: options[:group],
          feature_scope_feature_group: options[:feature_group],
          feature_scope_namespace: options[:namespace],
          feature_scope_repository: options[:repository]
        }
      end

      def issue_data(name:, environment:, options: {})
        event_scopes_hash(options).merge(
          username: username,
          now: Time.now.utc.iso8601,
          environment_host: "https://#{environment.gitlab_host}",
          rollout_issue_url: rollout_issue_url(name)
        )
      end

      def issue_description(name, value, environment, options)
        data = issue_data(name: name, environment: environment, options: options)

        description = [format(ISSUE_HEADER, data)]
        description.push(format(ISSUE_SCOPES_TABLE, data)) unless flag_was_deleted?(value)
        description.push(ISSUE_FOOTER).join("\n\n")
      end

      def feature_flag_definitions
        @feature_flag_definitions ||= {}
      end

      def feature_flag_definition?(feature_flag_name)
        feature_flag_definitions.key?(feature_flag_name)
      end

      def feature_flag_definition(feature_flag_name)
        return feature_flag_definitions[feature_flag_name] if feature_flag_definition?(feature_flag_name)

        feature_flag_definitions[feature_flag_name] = {}
        pattern = "#{feature_flag_name} f:\.yml$"
        search_results = production_api_client.search_in_project(MONOLITH_PROJECT, 'blobs', pattern)

        if search_results.any?
          logger.info(
            "Found #{search_results.size} files matching `#{pattern}`." \
            " `#{search_results.first[:path]}` will be fetched."
          )
          file_content = production_api_client.file_contents(MONOLITH_PROJECT, search_results.first[:path])

          feature_flag_definitions[feature_flag_name] = YAML.safe_load(file_contents) if file_content
        else
          logger.info("Found no files matching `#{pattern}`!")
        end

        feature_flag_definitions[feature_flag_name]
      end

      def rollout_issue_url(feature_flag_name)
        return unless feature_flag_definition?(feature_flag_name)

        feature_flag_definition(feature_flag_name)[:rollout_issue_url]
      end

      def rollout_issue_project_path(feature_flag_name)
        issue_url = rollout_issue_url(feature_flag_name)
        return unless issue_url

        matches = issue_url.match(ISSUE_REGEXP)
        return unless matches

        matches[:issue_project_path]
      end

      def rollout_issue_iid(feature_flag_name)
        issue_url = rollout_issue_url(feature_flag_name)
        return unless issue_url

        matches = issue_url.match(ISSUE_REGEXP)
        return unless matches

        matches[:issue_iid]
      end

      def enable_feature_value?(value)
        (value == 'true' || valid_numeric_value?(value) && (1..100).cover?(value.to_i))
      end

      def disable_feature_value?(value)
        %w[false 0].include?(value)
      end

      def feature_enabled_with_opts?(options, environment)
        feature_check = Chatops::Commands::Feature.new(['get', feature_name], options, env)
        feature = feature_check.get_feature(feature_name, environment)
        feature&.enabled?
      end

      def actors_or_random?(options)
        options[:actors] || options[:random]
      end

      def valid_numeric_value?(value)
        value.match?(/^\d+|\.$/)
      end

      def percentage_value?(value)
        valid_numeric_value?(value) && (0.0001..99).cover?(value.to_f)
      end

      def valid_setting_for_percentage_value?(value, options)
        return true unless percentage_value?(value)

        actors_or_random?(options)
      end

      def valid_actors_random_setting?(options)
        return true unless actors_or_random?(options)

        options.slice(:project, :group, :feature_group, :namespace, :user, :repository).compact.none?
      end

      def random_not_forced?(options)
        options[:random] && !options[:ignore_random_deprecation_check]
      end

      def production_check_status(pipeline_id)
        pipeline_jobs(pipeline_id).auto_paginate.each do |job|
          return job.status if job.name == AUTO_DEPLOY_CHECK_PRODUCTION_JOB
        end
      end

      def production_api_client
        @production_api_client ||= Environment.production.api_client
      end

      def feature_name
        return @feature_name if defined?(@feature_name)

        # backticks are used to escape Slack auto-converting string to emoji
        # so we strip them here if backticks surround the feature name
        # https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/24376#note_1555034145
        @feature_name = arguments[1]&.gsub(/^`(.*)`$/, '\1')
      end
    end
  end
end
