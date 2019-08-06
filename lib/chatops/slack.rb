# frozen_string_literal: true

module Chatops
  module Slack
    # Convenience method for returning a Slack Block Kit `mrkdwn` field.
    #
    # text - The Markdown text to render
    #
    # See https://api.slack.com/block-kit
    def self.markdown(text)
      {
        type: 'mrkdwn',
        text: text
      }
    end
  end
end
