# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Chatops::Commands::Zoekt do
  subject(:perform) do
    described_class.new(subcommand, {}, 'GITLAB_TOKEN' => 'the-token', 'CHAT_CHANNEL' => 'foo').perform
  end

  let(:env_options) { { dev: false, ops: false, pre: false, production: false, staging: false, staging_ref: false } }
  let(:gitlab_client) { instance_double(Chatops::Gitlab::Client) }

  RSpec.shared_examples 'validates required number of arguments' do
    it 'fails if we remove last argument' do
      subcommand.pop

      expect { perform }.to raise_error(ArgumentError)
    end
  end

  RSpec.shared_examples 'validates argument is integer' do |index|
    it "fails if we add letters to argument at index #{index}" do
      subcommand[index] += 'bad'

      expect { perform }.to raise_error(ArgumentError)
    end
  end

  describe 'indexed_namespace_create' do
    let(:subcommand) { %w[indexed_namespace_create 123 456] }

    it 'creates the indexed namespace' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: 'the-token', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:zoekt_shard_indexed_namespaces_create)
        .with(shard_id: 123, namespace_id: 456)
        .and_return(instance_double('indexed_namespace', zoekt_shard_id: 123, namespace_id: 456))

      expect(perform).to eq('Successfully created indexed namespace for shard 123 and namespace 456')
    end

    context 'when creation fails' do
      it 'returns an error message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'the-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:zoekt_shard_indexed_namespaces_create)
          .with(shard_id: 123, namespace_id: 456)
          .and_return(nil)

        expect(perform).to eq('Failed to create the indexed namespace for shard 123 and namespace 456')
      end
    end

    it_behaves_like 'validates required number of arguments'
    it_behaves_like 'validates argument is integer', 1
    it_behaves_like 'validates argument is integer', 2
  end

  describe 'force_index_project' do
    let(:subcommand) { %w[force_index_project 123] }

    it 'triggers indexing for the project' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: 'the-token', host: 'gitlab.com')
        .and_return(gitlab_client)

      expect(gitlab_client)
        .to receive(:zoekt_project_index)
        .with(project_id: 123)
        .and_return(instance_double('index_project_response', job_id: 'the-job-id'))

      expect(perform).to eq('Successfully triggered indexing for project 123 with job_id "the-job-id"')
    end

    context 'when creation fails' do
      it 'returns an error message' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'the-token', host: 'gitlab.com')
          .and_return(gitlab_client)

        expect(gitlab_client)
          .to receive(:zoekt_project_index)
          .with(project_id: 123)
          .and_return(nil)

        expect(perform).to eq('Failed to trigger indexing for project 123')
      end
    end

    it_behaves_like 'validates required number of arguments'
    it_behaves_like 'validates argument is integer', 1
  end

  describe '.available_subcommands' do
    it 'returns a Markdown list' do
      expect(described_class.available_subcommands).to eq(<<~LIST.strip)
        * force_index_project
        * indexed_namespace_create
      LIST
    end
  end
end
