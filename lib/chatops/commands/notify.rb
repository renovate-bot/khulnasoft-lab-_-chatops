# frozen_string_literal: true

module Chatops
  module Commands
    class Notify
      include Command

      CHANNELS = [
        'C02PF508L', # development
        'C3JJET4Q6', # test-platform
        'C8HG8D9MY', # backend
        'C0GQHHPGW', # frontend
        'C0XM5UU6B', # releases
        'CBQ76ND6W', # g_runner
        'C025LECQY0M', # g_dedicated_team
        'CNZPN8BT3', # sec-appsec
        'C248YCNCW' # security
      ].freeze

      usage "#{command_name} [MESSAGE] [OPTIONS]"
      description 'Sends a notification to various Slack channels'

      options do |o|
        o.separator <<~HELP.chomp

          Examples:

            notify "I made fried chicken, who would like some?"

          Note:

            If your message contains newlines, you must quote the entire
            message. Without quotes, the newlines will be removed.
        HELP
      end

      def perform
        message = arguments.join(' ')

        CHANNELS.each do |channel|
          Slack::Message
            .new(token: slack_token, channel: channel)
            .send(text: message)
        end

        # So we don't send the channel names back
        nil
      end
    end
  end
end
