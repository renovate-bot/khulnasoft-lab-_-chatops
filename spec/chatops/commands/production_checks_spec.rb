# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::ProductionChecks do
  describe '#perform' do
    let(:command) do
      described_class.new(
        [],
        {},
        'SLACK_TOKEN' => '123',
        'CHAT_CHANNEL' => '456'
      )
    end
    let(:slack_msg) { instance_spy(Chatops::Slack::Message) }

    it 'performs a production check' do
      expect(command).to receive(:run_trigger).with(CHECK_PRODUCTION: 'true', PRODUCTION_CHECK_SCOPE: 'deployment')
      expect(command.perform)
        .to eq('Production checks triggered, the results will appear shortly.')
    end
  end
end
