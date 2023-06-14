# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Migrations do
  let(:default_options) do
    {
      'GITLAB_TOKEN' => 'gitlab-token',
      'SLACK_TOKEN' => 'slack-token',
      'CHAT_CHANNEL' => 'foo'
    }
  end

  describe '#perform' do
    subject(:perform) do
      described_class.new(subcommand, {}, default_options).perform
    end

    let(:env_options) do
      {
        dev: false,
        ops: false,
        pre: false,
        production: false,
        staging: false,
        staging_ref: false
      }
    end

    let(:subcommand) { %w[mark] }

    context 'when it is a valid instruction' do
      let(:gitlab_client) { instance_double('gitlab_client') }
      let(:slack_client) { instance_double('slack_client') }

      it 'runs the subcommand' do
        instance = described_class.new(subcommand)

        expect(instance).to receive(:mark)

        instance.perform
      end
    end

    context 'when the command does not exist' do
      let(:subcommand) { %w[missing_command] }

      it 'returns an error message' do
        expect(perform).to include('The migrations subcommand `missing_command` is invalid')
      end
    end

    it 'supports environment options' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(subcommand, { database: nil }.merge(env_options), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(subcommand)
    end

    it 'supports --database option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(subcommand, { database: 'ci' }.merge(env_options), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[mark --database ci])
    end
  end

  describe '#mark' do
    context 'when not specifying a version number' do
      it 'returns an error message' do
        command = described_class.new(%w[mark])

        expect(command.mark).to match(/You must specify the version number of the migration/)
      end
    end

    context 'when specifying an invalid value' do
      it 'returns an error message' do
        command = described_class.new(%w[mark bar], {})

        expect(command.mark).to match(/The value 'bar' is invalid/)
      end
    end

    context 'with a valid value' do
      subject(:mark) do
        described_class.new(subcommand, {}, default_options).perform
      end

      let(:migration_input) { 20_230_428_500_000 }
      let(:subcommand) { %W[mark #{migration_input}] }
      let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
      let(:slack_client) { instance_double(Chatops::Slack::Message) }

      before do
        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'gitlab-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        allow(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: 'slack-token', channel: 'foo')
          .and_return(slack_client)
      end

      it 'marks a migration' do
        expect(gitlab_client)
          .to receive(:mark_database_migration_by_version)
          .with(migration_input.to_s, database: 'main')
          .and_return(instance_double('response', message: '201 Created'))

        expect(slack_client)
          .to receive(:send)
          .with(text: 'Migration "20230428500000" was marked as successfully executed on gprd.')

        expect(mark).to be_nil
      end

      it 'returns an appropriate response when the migration does not exist' do
        expect(gitlab_client)
          .to receive(:mark_database_migration_by_version)
          .with(migration_input.to_s, database: 'main')
          .and_return(nil)

        expect(slack_client)
          .to receive(:send)
          .with(text: 'The migration "20230428500000" does not exist on gprd.')

        expect(mark).to be_nil
      end

      it 'returns an appropriate response if the migration cannot be marked' do
        expect(gitlab_client)
          .to receive(:mark_database_migration_by_version)
          .with(migration_input.to_s, database: 'main')
          .and_raise(gitlab_error(:ResponseError, message: 'Oh no!'))

        expect(slack_client)
          .to receive(:send)
          .with(text: 'Failed to mark the migration "20230428500000" on gprd, the error was: "Oh no!".')

        expect(mark).to be_nil
      end
    end
  end
end
