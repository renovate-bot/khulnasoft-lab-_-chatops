# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Rollback, :release_command do
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

    it 'triggers a check for the specified environment' do
      instance = stubbed_instance('check', 'gprd')

      expect(instance).to receive(:trigger_release)
        .with(nil, 'auto_deploy:rollback_check', ROLLBACK_TARGET: nil, ROLLBACK_ENV: 'gprd')

      instance.perform
    end

    it 'triggers a check for the specified target' do
      instance = stubbed_instance('check', 'gprd', target: '42.1.2021121314+f7e5665fa11.3fb2052b8b6')

      expect(instance).to receive(:trigger_release)
        .with(
          nil,
          'auto_deploy:rollback_check',
          ROLLBACK_TARGET: '42.1.2021121314+f7e5665fa11.3fb2052b8b6',
          ROLLBACK_ENV: 'gprd'
        )

      instance.perform
    end
  end
end
