# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::PostDeployMigrations do
  let(:env) do
    [
      {},
      'SLACK_TOKEN' => 'token',
      'CHAT_CHANNEL' => 'channel',
      'GITLAB_TOKEN' => 'token',
      'GITLAB_OPS_TOKEN' => 'token',
      'RELEASE_TRIGGER_TOKEN' => 'token'
    ]
  end

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
        command = described_class.new(%w[execute])

        expect(command).to receive(:execute)

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
      expect(described_class.available_subcommands).to include('* execute')
    end
  end

  describe '#execute' do
    let(:command) { described_class.new(%w[execute], *env) }

    it 'triggers the post deploy migrations pipeline' do
      expect(command)
        .to receive(:run_trigger)
        .with(POSTDEPLOY_PIPELINE: 'true')
        .and_return(instance_double('gitlab_response', web_url: 'test_url'))

      expect(command.perform).to eq('The post-deploy migration pipeline has started: test_url')
    end
  end
end
