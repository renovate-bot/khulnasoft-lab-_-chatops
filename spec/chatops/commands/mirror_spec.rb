# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Mirror do
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
        command = described_class.new(%w[status])

        expect(command)
          .to receive(:status)

        expect(command.perform).to be_nil
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
    subject(:command) { described_class.new(%w[status], *env) }

    let(:env) do
      [
        {},
        'GITLAB_OPS_TOKEN' => 'ops-token',
        'RELEASE_TRIGGER_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel'
      ]
    end

    # rubocop:disable RSpec/VerifiedDoubles
    let(:fake_client) { double('Chatops::Gitlab::Client').as_null_object }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    it 'triggers a pipeline on release-tools' do
      expect(fake_client).to receive(:new).with(
        token: 'ops-token',
        host: Chatops::GitlabEnvironments::OPS_HOST
      )

      expect(fake_client)
        .to receive(:run_trigger).with(
          described_class::TARGET_PROJECT,
          'token',
          described_class::TARGET_REF,
          {
            CHAT_CHANNEL: 'channel',
            MIRROR_STATUS: 'true'
          }
        )

      command.perform
    end
  end
end
