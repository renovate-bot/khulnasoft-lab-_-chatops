# frozen_string_literal: true

module Chatops
  module Commands
    class Feature
      include Command
      include GitlabEnvironments

      # The color to use for the attachment containing enabled features.
      ENABLED_COLOR = '#B3ED8E'

      # The color to use for the attachment containing disabled features.
      DISABLED_COLOR = '#ccc'

      # All the available subcommands and the corresponding methods to invoke.
      COMMANDS = Set.new(%w[get set list delete])

      # The URL to the Gates documentation, to be displayed when retrieving a
      # single feature.
      GATES_DOCUMENTATION = 'https://github.com/jnunemaker/flipper/blob/master/docs/Gates.md'

      # The project name to use for logging the toggling of feature flags.
      LOG_PROJECT = 'gitlab-com/gl-infra/feature-flag-log'

      # The project used for recording ongoing production incidents.
      INCIDENTS_PROJECT = 'gitlab-com/gl-infra/production'

      # The severity labels applied to an incident issue before it blocks
      # changing feature flags.
      SEVERITY_LABELS = %w[severity::1 severity::2].freeze

      # IDs of QA channels to send message each time a feature flag is set
      QA_CHANNELS = {
        STAGING_HOST => 'CBS3YKMGD', # `#qa-staging`
        PRODUCTION_HOST => 'CCNNKFP8B' # `#qa-production`
      }.freeze

      FEATURE_FLAG_PROPAGATION_WARNING =
        ' (Due to ' \
        '`https://gitlab.com/gitlab-org/gitlab/-/issues/325452`, ' \
        'this may not take effect immediately. ' \
        'See the issue for details and a workaround.)'

      description 'Managing of GitLab feature flags.'

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
          '--user',
          'The username of a user to set a feature flag for, e.g. someuser'
        )
        o.bool('--actors',
               'Modifier to roll out a feature flag to a percentage of actors')

        o.boolean(
          '--ignore-incidents',
          "Ignore any ongoing incidents when changing a feature flag's state"
        )

        GitlabEnvironments.define_environment_options(o)

        o.separator("\nAvailable subcommands:\n\n#{available_subcommands}")
      end

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

          # To enable a feature 50% of the time:
          feature set gitaly_tags 50

          # To enable a feature 50% of the actors:
          feature set gitaly_tags 50 --actors

          # To enable a feature for a project
          feature set --project=gitlab-org/gitaly gitaly_tags

          # To enable a feature for a group
          feature set --group=gitlab-org gitaly_tags

          # To enable a feature for a user
          feature set --user=someuser gitaly_tags

          # To delete a feature flag and return to default behaviour:
          feature delete gitaly_tags
          ```

          For more information run `feature --help`.
        MESSAGE
      end

      # Retrieves details of a single feature flag.
      def get
        name = arguments[1]

        unless name
          return 'You must specify the name of the feature. ' \
            'For example: `feature get gitaly_tags`'
        end

        feature = Gitlab::FeatureCollection
          .new(token: gitlab_token, host: gitlab_host)
          .find_by_name(name)

        return "The feature #{name.inspect} does not exist." unless feature

        send_feature_details(feature: feature)
      end

      # Updates the value of a single feature flag.
      def set
        name = arguments[1]
        value = arguments[2]

        if !name || !value
          return 'You must specify the name of the feature flag ' \
            'and its new value.'
        end

        unless Gitlab::Feature.valid_value?(value)
          return "The value #{value.inspect} is invalid. " \
            'Valid values are: `true`, `false`, or an integer from 0 to 100.'
        end

        if ongoing_incidents?
          return "This feature flag's state can't be changed as one or more " \
            'production incidents are ongoing. If you absolutely must change ' \
            'the state of this feature flag, ' \
            'please confirm with the current SRE ' \
            'oncall `@sre-oncall`, and use the --ignore-incidents option. ' \
            'See the <https://gitlab.com' \
            '/gitlab-com/gl-infra/production/-/issues?label_name%5B%5D=' \
            'Incident%3A%3AActive|list of currently active incidents>'
        end

        response = Gitlab::Client
          .new(token: gitlab_token, host: gitlab_host)
          .set_feature(name, value, project: options[:project],
                                    group: options[:group],
                                    user: options[:user],
                                    actors: options[:actors])

        feature = Gitlab::Feature.from_api_response(response)
        perform_side_effects(name, value, feature)
      end

      def perform_side_effects(name, value, feature)
        annotate_feature_toggle(name, value)
        send_feature_toggle_event(name, value)
        issue = log_feature_toggle(name, value)

        output = []
        output << send_feature_details(
          feature: feature,
          text: 'The feature flag value has been updated!' +
                FEATURE_FLAG_PROPAGATION_WARNING
        )

        output << send_feature_toggling_to_qa_channel(issue)

        output.compact.join("\n")
      end

      # Lists all the available feature flags per state.
      def list
        enabled, disabled = attachment_fields_per_state

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
                footer: "#{enabled.length} enabled features on #{gitlab_host}"
              },
              {
                title: 'Disabled Features',
                text: 'These features are disabled:',
                fields: disabled,
                color: DISABLED_COLOR,
                footer: "#{disabled.length} disabled features on #{gitlab_host}"
              }
            ]
          }
        )
      end

      # Remove a feature flag
      #
      # Idempotent request, deleting non existing flags seems successful
      def delete
        name = arguments[1]

        Gitlab::Client
          .new(token: gitlab_token, host: gitlab_host)
          .delete_feature(name)

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: {
            text: "Feature flag #{name} has been removed from #{gitlab_host}!"
          }
        )
      end

      # Sends the details of a single feature back to Slack.
      #
      # feature - A `Chatops::Gitlab::Feature` instance containing the details
      #           we want to send back.
      # text - Optional text to include in the message.
      def send_feature_details(feature:, text: nil)
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
                footer: "Host: #{gitlab_host}"
              }
            ]
          }
        )
      end

      def send_feature_toggling_to_qa_channel(issue)
        channel = QA_CHANNELS[gitlab_host]
        return unless channel

        blocks = [{
          type: 'section',
          text: Slack.markdown("<#{issue.web_url}|#{issue.title}>")
        }]

        send_slack_message_safely(
          slack_token: slack_token,
          channel: channel,
          slack_args: { blocks: blocks }
        )
      end

      def send_slack_message_safely(slack_token:, channel:, slack_args:)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(**slack_args)
      rescue Slack::Message::MessageError => error
        'The following Slack message could not be posted to channel ' \
        "'#{channel}': #{slack_args}\n\nError: #{error.message}"
      end

      def attachment_fields_per_state
        Gitlab::FeatureCollection
          .new(token: gitlab_token, match: options[:match], host: gitlab_host)
          .per_state
          .map { |vals| vals.map(&:to_attachment_field) }
      end

      def send_feature_toggle_event(name, value)
        return unless staging? || production?

        message = "feature '#{name}' updated to '#{value}'"
        Chatops::Events::Client
          .new(env_name)
          .send_event(
            message,
            fields: {
              'feature_name' => name,
              'feature_value' => value.to_s
            }
          )
      end

      def log_feature_toggle(name, value)
        client = Gitlab::Client
          .new(token: env.fetch('GITLAB_TOKEN'), host: PRODUCTION_HOST)

        host = gitlab_host
        username = env.fetch('GITLAB_USER_LOGIN')
        labels = "host::#{host}, change"

        description = <<~DESC
          * Feature flag: `#{name}`
          * New value: `#{value}`
          * Percentage of actors: `#{options[:actors]}`
          * Changed by: [`@#{username}`](https://gitlab.com/#{username})
          * Changed on (in UTC): `#{Time.now.utc.iso8601}`
          * Host: https://#{host}

          ## Feature flag scopes

          This feature flag applies the following scopes (if any):

          | User                        | Project                        | Group
          |-----------------------------|--------------------------------|-------------
          | `#{options[:user].inspect}` | `#{options[:project].inspect}` | `#{options[:group].inspect}`

          When a value is set to `nil` it means the scope does not apply. If
          none of these scopes are set it means the feature flag applies to
          everybody.

          <hr>

          :robot: This issue was generated using [GitLab
          Chatops](https://gitlab.com/gitlab-com/chatops/).
        DESC

        if options[:ignore_incidents]
          labels += ', Incidents ignored'

          description = ':warning: **This feature flag was changed despite ' \
            'there being one or more ongoing production incidents.**' \
            "\n\n#{description}"
        end

        issue = client.create_issue(
          LOG_PROJECT,
          "Feature flag #{name.inspect} has been set to #{value.inspect}",
          labels: labels,
          description: description
        )

        client.close_issue(issue.project_id, issue.iid)

        issue
      end

      def annotate_feature_toggle(name, value)
        Grafana::Annotate.new(token: grafana_token)
          .annotate!(
            "#{username} set feature flag #{name} to #{value}",
            tags: [env_name, 'feature-flag', name]
          )
      end

      def username
        env.fetch('GITLAB_USER_LOGIN')
      end

      def ongoing_incidents?
        return false if options[:ignore_incidents]

        return false if env_name != 'gprd'

        Gitlab::Client
          .new(token: env.fetch('GITLAB_TOKEN'), host: PRODUCTION_HOST)
          .issues(INCIDENTS_PROJECT, labels: 'Incident::Active', state: 'opened') # rubocop:disable Metrics/LineLength
          .auto_paginate do |issue|
            return true if (issue.labels & SEVERITY_LABELS).any?
          end

        false
      end
    end
  end
end
