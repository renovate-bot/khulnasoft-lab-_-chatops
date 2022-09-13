# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Chatops::Commands::BatchedBackgroundMigrations do
  describe '#perform' do
    subject(:perform) do
      described_class.new(subcommand, {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }
    let(:subcommand) { %w[list] }

    context 'when it is a valid instruction' do
      let(:gitlab_client) { instance_double('gitlab_client') }
      let(:slack_client) { instance_double('slack_client') }

      it 'runs the subcommand' do
        instance = described_class.new(subcommand)

        expect(instance).to receive(:list)

        instance.perform
      end

      it 'sends a slack message' do
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

        perform
      end
    end

    context 'when the command does not exist' do
      let(:subcommand) { %w[wrong] }

      it 'returns an error message' do
        expect(perform).to include('The batched background migration subcommand is invalid')
      end
    end
  end

  describe '#resume' do
    subject(:resume) do
      described_class.new(%w[resume], {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:gitlab_client) { instance_double('gitlab_client') }
    let(:slack_client) { instance_double('slack_client') }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }

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
      described_class.new(%w[status], {}, 'GITLAB_TOKEN' => '123', 'SLACK_TOKEN' => '456', 'CHAT_CHANNEL' => 'foo').perform
    end

    let(:gitlab_client) { instance_double('gitlab_client') }
    let(:slack_client) { instance_double(Chatops::Slack::Message) }
    let(:migration) { instance_double('migration', id: 1, job_class_name: 'a', table_name: 'b', status: 'b', progress: 1, created_at: Time.now) }

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
end
