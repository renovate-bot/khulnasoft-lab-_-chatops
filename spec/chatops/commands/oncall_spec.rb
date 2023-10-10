# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Oncall do
  describe '#perform' do
    let(:client) do
      instance_spy(
        Chatops::PagerDuty::Client,
        services: double.as_null_object,
        oncalls: double.as_null_object
      )
    end

    let(:env) do
      {
        'CHAT_CHANNEL' => 'C0123456',
        'PAGERDUTY_TOKEN' => 'pd_token',
        'SLACK_TOKEN' => 'slack_token'
      }
    end

    before do
      allow(Chatops::Slack::Message).to receive(:new)
        .and_return(instance_double(Chatops::Slack::Message, send: true))
    end

    it 'passes a query to services' do
      command = described_class.new(%w[query], {}, env)

      allow(command).to receive(:client).and_return(client)
      command.perform

      expect(client).to have_received(:services).with('query')
    end

    it 'posts oncall details' do
      command = described_class.new([], {}, env)
      client = instance_double(
        Chatops::PagerDuty::Client,
        services: %w[services],
        oncalls: %w[oncalls]
      )

      allow(command).to receive(:client).and_return(client)
      expect(command).to receive(:build_attachments)
        .with(%w[services])
        .and_return(%w[details])
      expect(command).to receive(:respond).with(['details'])

      command.perform
    end
  end
end
