# frozen_string_literal: true

module SlackMessageHelpers
  def expect_slack_message(args = {})
    message = instance_double('Chatops::Slack::Message')

    expect(Chatops::Slack::Message)
      .to receive(:new)
      .and_return(message)

    expect(message)
      .to receive(:send)
      .with(**args)
  end
end

RSpec.configure do |c|
  c.include SlackMessageHelpers
end
