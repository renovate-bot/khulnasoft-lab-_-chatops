# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Rollback do
  let(:fake_client) { spy }

  let(:env) do
    [
      {},
      'SLACK_TOKEN' => 'token',
      'CHAT_CHANNEL' => 'channel',
      'GITLAB_TOKEN' => 'token'
    ]
  end

  before do
    stub_const('Chatops::Gitlab::Client', fake_client)
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
        command = described_class.new(%w[check gprd])

        expect(command)
          .to receive(:check)
          .with('gprd')

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
      expect(described_class.available_subcommands).to include('* check')
    end
  end

  describe '#check' do
    it 'returns an error for an invalid environment' do
      command = described_class.new(%w[check fake_env])

      expect(command.perform).to match('Invalid environment')
    end

    it 'compares the latest deployments' do
      command = described_class.new(%w[check gprd], *env)

      deployments = [
        instance_double('deployment', sha: 'abcdefg'),
        instance_double('deployment', sha: '1234567')
      ]
      compare = instance_double('compare', diffs: [], compare_timeout: false)

      expect(fake_client).to receive(:latest_deployments)
        .with(described_class::SOURCE_PROJECT, 'gprd', status: 'success', limit: 2)
        .and_return(deployments)
      expect(fake_client).to receive(:latest_deployments)
        .with(described_class::SOURCE_PROJECT, 'gprd', status: 'running', limit: 1)
        .and_return([])

      expect(fake_client).to receive(:compare)
        .with(described_class::SOURCE_PROJECT, '1234567', 'abcdefg')
        .and_return(compare)

      expect(Chatops::Gitlab::RollbackCheck).to receive(:new)
        .with(compare, nil)
        .and_call_original

      expect_slack_message(blocks: RollbackBlockMatcher.new('gprd'))

      command.perform
    end

    it 'includes a running deployment' do
      command = described_class.new(%w[check gprd], *env)

      running = instance_double('deployment', sha: 'a1b2c3d4')
      deployments = [
        instance_double('deployment', sha: 'abcdefg'),
        instance_double('deployment', sha: '1234567')
      ]
      compare = instance_double('compare', diffs: [], compare_timeout: false)

      expect(fake_client).to receive(:latest_deployments)
        .with(described_class::SOURCE_PROJECT, 'gprd', status: 'success', limit: 2)
        .and_return(deployments)
      expect(fake_client).to receive(:latest_deployments)
        .with(described_class::SOURCE_PROJECT, 'gprd', status: 'running', limit: 1)
        .and_return([running])

      expect(fake_client).to receive(:compare)
        .with(described_class::SOURCE_PROJECT, '1234567', 'abcdefg')
        .and_return(compare)

      expect(Chatops::Gitlab::RollbackCheck).to receive(:new)
        .with(compare, running)
        .and_call_original

      expect_slack_message(blocks: RollbackBlockMatcher.new('gprd'))

      command.perform
    end
  end
end

class RollbackBlockMatcher
  def initialize(env)
    @env = env
  end

  def ===(other)
    other.to_json.include?(":party-tanuki: #{@env}")
  end
end
