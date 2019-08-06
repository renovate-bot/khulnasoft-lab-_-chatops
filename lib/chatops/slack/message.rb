# frozen_string_literal: true

module Chatops
  module Slack
    # A Message can be used to manually send a message to a Slack channel.
    class Message
      # The URL to send the message to.
      API_URL = 'https://slack.com/api/chat.postMessage'

      # Error to be raised whenever a message could not be sent.
      MessageError = Class.new(StandardError)

      # token - The API token to use for submitting the message.
      # channel - The channel to send the message to.
      def initialize(token:, channel:)
        @token = token
        @channel = channel
      end

      # message - The message to send.
      # attachments - Any attachments to include in the message.
      # blocks - Any blocks to include in the message.
      def send(text: nil, attachments: [], blocks: [])
        response = HTTP.post(
          API_URL,
          headers: {
            accept: 'application/json',
            content_type: 'application/json',
            authorization: "Bearer #{@token}"
          },
          body: {
            channel: @channel,
            response_type: :in_channel,
            as_user: true,
            text: text,
            attachments: attachments,
            blocks: blocks
          }.to_json
        )

        body = JSON.parse(response.body)

        raise(MessageError, body['error']) unless body['ok']
      end
    end
  end
end
