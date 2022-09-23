# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Chatops::Commands::BatchedBackgroundMigrations do
  describe '#perform' do
    subject(:perform) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
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
      let(:subcommand) { %w[wrong] }

      it 'returns an error message' do
        expect(perform).to include('The batched background migration subcommand is invalid')
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
        .with(subcommand, { database: 'main' }.merge(env_options), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[list --database main])
    end
  end

  describe '#list' do
    subject(:list) do
      described_class.new(command, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:command) { %w[list] }
    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }

    it 'list migrations' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '123', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:batched_background_migrations)
        .and_return([migration])

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(slack_client)

      expect(slack_client).to receive(:send)

      list
    end
  end

  describe '#resume' do
    subject(:resume) do
      described_class.new(command, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }
    let(:command) { %w[resume 1] }

    context 'when the migration does not exist' do
      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:resume_batched_background_migration)
          .and_return(nil)

        expect(resume).to eql('Migration not found')
      end
    end

    context 'when the migration id is not present' do
      let(:command) { %w[resume] }
      let(:message) { 'Please provide a migration ID to the resume command.' }

      it 'returns a message' do
        expect(resume).to eql(message)
      end
    end

    it 'resumes the migration' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '123', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:resume_batched_background_migration)
        .and_return(migration)

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(slack_client)

      expect(slack_client).to receive(:send)

      resume
    end
  end

  describe '#status' do
    subject(:status) do
      described_class.new(command, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }
    let(:command) { %w[status 1] }

    context 'when the migration does not exist' do
      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:batched_background_migration)
          .and_return(nil)

        expect(status).to eql('Migration not found')
      end
    end

    context 'when the migration id is not present' do
      let(:command) { %w[status] }
      let(:message) { 'Please provide a migration ID to the status command.' }

      it 'returns a message' do
        expect(status).to eql(message)
      end
    end

    it 'returns the migration' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '123', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:batched_background_migration)
        .and_return(migration)

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(slack_client)

      expect(slack_client).to receive(:send)

      status
    end
  end

  describe '#pause' do
    subject(:pause) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:subcommand) { %w[pause 1] }
    let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }

    context 'when the migration does not exist' do
      it 'returns a message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:pause_batched_background_migration)
          .and_return(nil)

        expect(pause).to eql('Migration not found')
      end
    end

    context 'when the migration id is not present' do
      let(:subcommand) { %w[pause] }
      let(:message) { 'Please provide a migration ID to the pause command.' }

      it 'returns a message' do
        expect(pause).to eql(message)
      end
    end

    it 'pauses the migration' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '123', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:pause_batched_background_migration)
        .and_return(migration)

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(slack_client)

      expect(slack_client).to receive(:send)

      pause
    end
  end
end
