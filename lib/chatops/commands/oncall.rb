# frozen_string_literal: true

module Chatops
  module Commands
    class Oncall
      include Command

      usage "#{command_name} [service]"
      description 'List PagerDuty oncalls.'

      def perform
        search = arguments[0]

        services = client.services(search)

        attachments = build_attachments(services)
        respond(attachments)
      end

      private

      def client
        @client ||= PagerDuty::Client.new(pagerduty_token)
      end

      def build_attachments(services)
        attachments = []

        services.each do |service|
          attachments << {
            pretext: "Oncall for #{service['name']}",
            fallback: "Oncall for #{service['name']}"
          }

          oncalls_for_service(service).each do |oncall|
            attachments << {
              author_icon: oncall.avatar_url,
              author_link: "mailto:#{oncall.email}",
              author_name: "#{oncall.name} - #{oncall.escalation_title}",
              color: oncall.escalation_color,
              fallback: oncall.name
            }
          end
        end

        attachments
      end

      def respond(attachments)
        Slack::Message.new(token: slack_token, channel: channel)
          .send(attachments: attachments)
      end

      def oncalls
        @oncalls ||= client.oncalls
      end

      # Return an array of oncall Users with the same escalation policy as the
      # specified service
      def oncalls_for_service(service)
        policy_id = service['escalation_policy']['id']

        oncalls
          .select { |oncall| oncall['escalation_policy']['id'] == policy_id }
          .map { |oncall| PagerDuty::User.new(oncall) }
          .sort_by(&:escalation_level)
      end
    end
  end
end
