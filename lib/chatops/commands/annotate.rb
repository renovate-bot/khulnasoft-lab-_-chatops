# frozen_string_literal: true

module Chatops
  module Commands
    class Annotate
      include Command
      include GitlabEnvironments

      usage "#{command_name} [TEXT] --dashboard-uids ABC123,DEF456 [OPTIONS]"
      description 'Create a custom Grafana annotation.'

      options do |o|
        o.array(
          '--dashboard-uids',
          'Comma separated list of Grafana dashboard UIDs on which ' \
            'the annotation should appear. The UID is an alphanumeric string ' \
            'found in the dashboard URL.',
          required: true,
          delimiter: ','
        )

        GitlabEnvironments.define_environment_options(o)
      end

      def perform
        user_text = arguments.join(' ').strip

        unless user_text && !user_text.empty?
          return 'You need to provide text to create an annotation'
        end

        dashboard_ids = resolve_dashboard_ids

        user_link = "<a href=\"https://gitlab.com/#{username}\">@#{username}</a>" # rubocop:disable Metrics/LineLength
        annotation_text = "#{user_text} (#{user_link})"
        annotate = Grafana::Annotate.new(token: grafana_token)

        dashboard_ids.each do |id|
          annotate.annotate!(
            annotation_text,
            tags: ['user-annotation', env_name],
            dashboard_id: id
          )
        end

        slack_success!(dashboard_ids)
      end

      def username
        env.fetch('GITLAB_USER_LOGIN')
      end

      private

      def resolve_dashboard_ids
        options[:dashboard_uids].map do |uid|
          dashboard = Grafana::Dashboard.new(token: grafana_token)
          result = dashboard.find_by_uid(uid)
          result['dashboard']['id']
        end
      end

      def slack_success!(dashboard_ids)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
            text: ':grafana: Success',
            attachments: [
              {
                text: "Annotated #{dashboard_ids.size} dashboards"
              }
            ]
          )
      end
    end
  end
end
