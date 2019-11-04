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
            'Valid valures are: `true`, `false`, or an integer from 0 to 100.'
        end

        response = Gitlab::Client
          .new(token: gitlab_token, host: gitlab_host)
          .set_feature(name, value, project: options[:project],
                                    group: options[:group],
                                    user: options[:user])

        feature = Gitlab::Feature.from_api_response(response)

        send_feature_details(
          feature: feature,
          text: 'The feature flag value has been updated!'
        )
      end

      # Lists all the available feature flags per state.
      def list
        enabled, disabled = attachment_fields_per_state

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
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

        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(text: "Feature flag #{name} has been removed!")
      end

      # Sends the details of a single feature back to Slack.
      #
      # feature - A `Chatops::Gitlab::Feature` instance containing the details
      #           we want to send back.
      # text - Optional text to include in the message.
      def send_feature_details(feature:, text: nil)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
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
          )
      end

      def attachment_fields_per_state
        Gitlab::FeatureCollection
          .new(token: gitlab_token, match: options[:match], host: gitlab_host)
          .per_state
          .map { |vals| vals.map(&:to_attachment_field) }
      end
    end
  end
end
