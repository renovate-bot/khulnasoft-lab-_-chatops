# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::SearchMigrations do
  describe '#perform' do
    subject(:perform) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => 'gitlab-token', 'SLACK_TOKEN' => 'slack-token', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }
    let(:subcommand) { %w[list] }
    let(:env_options) { { dev: false, ops: false, pre: false, production: false, staging: false, staging_ref: false } }

    context 'when it is a valid instruction' do
      let(:gitlab_client) { instance_double('gitlab_client') }
      let(:slack_client) { instance_double('slack_client') }

      it 'runs the subcommand' do
        instance = described_class.new(subcommand)

        expect(instance).to receive(:list)

        instance.perform
      end
    end

    context 'when the command does not exist' do
      let(:subcommand) { %w[missing_command] }

      it 'returns an error message' do
        expect(perform).to include('The search_migrations subcommand is invalid')
      end
    end

    it 'supports environment options' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(subcommand, env_options, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(subcommand)
    end
  end

  describe '#list' do
    subject(:list) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => 'gitlab-token', 'SLACK_TOKEN' => 'slack-token', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:subcommand) { %w[list] }
    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) do
      instance_double('migration', version: 12_345,
                                   name: 'SearchMigration', completed: true, obsolete: false,
                                   started_at: Time.now, completed_at: Time.now, migration_state: { foo: 'bar' })
    end

    it 'list migrations' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: 'gitlab-token', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:search_migrations)
        .and_return([migration])

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: 'slack-token', channel: 'foo')
        .and_return(slack_client)

      expect(slack_client).to receive(:send)

      expect(list).to be_nil
    end

    context 'when there are no search migrations' do
      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'gitlab-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:search_migrations)
          .and_return([])

        expect(Chatops::Slack::Message)
          .not_to receive(:new)
          .with(token: 'slack-token', channel: 'foo')

        expect(list).to eq('There are no search migrations in the system')
      end
    end
  end

  describe '#get' do
    subject(:get) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => 'gitlab-token', 'SLACK_TOKEN' => 'slack-token', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:migration_input) { 12_345 }
    let(:subcommand) { %W[get #{migration_input}] }
    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) do
      instance_double('migration', version: 12_345,
                                   name: 'SearchMigration', completed: true, obsolete: false,
                                   started_at: Time.now, completed_at: Time.now, migration_state: { foo: 'bar' })
    end

    shared_examples 'a command that fetches a migration' do
      it 'gets a migration' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'gitlab-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:find_search_migration_by_version_or_name)
          .with(migration_input)
          .and_return(migration)

        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: 'slack-token', channel: 'foo')
          .and_return(slack_client)

        expect(slack_client).to receive(:send)

        expect(get).to be_nil
      end
    end

    context 'when passed a number' do
      let(:migration_input) { '12345' }

      it_behaves_like 'a command that fetches a migration'
    end

    context 'when passed a title case string' do
      let(:migration_input) { 'SearchMigration' }

      it_behaves_like 'a command that fetches a migration'
    end

    context 'when passed a snake case string' do
      let(:migration_input) { 'search_migration' }

      it_behaves_like 'a command that fetches a migration'
    end

    context 'when passed a non alphanumeric character' do
      let(:subcommand) { %w[get test$_1234] }

      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .not_to receive(:new)

        expect(gitlab_client).not_to receive(:find_search_migration_by_version_or_name)

        expect(Chatops::Slack::Message).not_to receive(:new)

        expect(get).to include('You must specify the version or name of the search migration')
      end
    end

    context 'when no migration name or version is provided' do
      let(:subcommand) { %w[get] }

      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .not_to receive(:new)

        expect(gitlab_client).not_to receive(:find_search_migration_by_version_or_name)

        expect(Chatops::Slack::Message).not_to receive(:new)

        expect(get).to include('You must specify the version or name of the search migration')
      end
    end

    context 'when migration is not found' do
      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'gitlab-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:find_search_migration_by_version_or_name)
          .with('12345')
          .and_return(nil)

        expect(Chatops::Slack::Message).not_to receive(:new)

        expect(get).to eq('The migration "12345" does not exist on gprd.')
      end
    end
  end
end
