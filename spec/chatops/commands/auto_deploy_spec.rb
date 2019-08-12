# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::AutoDeploy do
  describe '.perform' do
    it 'includes examples in the --help output' do
      output = described_class.perform(%w[--help])

      expect(output).to include('Available subcommands:')
      expect(output).to include('Examples:')
    end
  end

  describe '#perform' do
    context 'when using a valid subcommand' do
      it 'executes the subcommand' do
        command = described_class.new(%w[status c01bc1930])

        expect(command)
          .to receive(:status)
          .with('c01bc1930')

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[not_a_real_command])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* status')
    end
  end

  describe '#status' do
    let(:fake_client) { class_double('Gitlab::Client').as_null_object }
    let(:production_status) do
      {
        host: 'gitlab.com',
        version: '12.2.0-pre',
        revision: '0874a8d346c',
        branch: '12-2-auto-deploy-20190804'
      }
    end

    before do
      stub_const('Gitlab::Client', fake_client)
    end

    context 'with no argument' do
      let(:command) do
        described_class.new(
          %w[status],
          {},
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456',
          'GITLAB_TOKEN' => 'token'
        )
      end

      before do
        allow(command).to receive(:environment_status)
          .and_return(production_status)
      end

      it 'send a formatted Slack message' do
        message = instance_double('message')

        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: '456')
          .and_return(message)

        expect(message)
          .to receive(:send)
          .with(blocks: StatusBlockArgumentMatcher.new(production_status))

        command.perform
      end
    end
  end
end

# RSpec argument matcher for verifying the complex `block` Hash passed to
# `Slack::Message#send` from the described class
class StatusBlockArgumentMatcher
  def initialize(status)
    @status = status
  end

  def ===(other)
    json = other.to_json

    json.include?(':party-tanuki:') &&
      json.include?("<https://#{@status[:host]}/|#{@status[:host]}>") &&
      json.include?(@status[:version]) &&
      json.include?(@status[:revision]) &&
      json.include?(@status[:branch])
  end
end
