# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Chatops::Commands::Notify do
  describe '#perform' do
    it 'sends a message to various channels' do
      described_class::CHANNELS.each do |channel|
        spy = instance_spy(Chatops::Slack::Message)

        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: 'hunter2', channel: channel)
          .and_return(spy)

        expect(spy).to receive(:send).with(text: 'foo bar')
      end

      command = described_class.new(%w[foo bar], {}, 'SLACK_TOKEN' => 'hunter2')

      expect(command.perform).to be_nil
    end
  end
end
