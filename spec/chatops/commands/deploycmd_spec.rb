# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Deploycmd do
  describe '.perform' do
    it 'supports a --production option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(production: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--production])
    end

    it 'supports a --canary option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(canary: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--canary])
    end

    it 'supports a --dr option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(dr: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--dr])
    end

    it 'supports a --pre option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(pre: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--pre])
    end

    it 'supports a --list' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(list: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--list])
    end

    it 'supports a --no-check' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(no_check: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--no-check])
    end

    it 'supports a --skip-haproxy' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(skip_haproxy: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--skip-haproxy])
    end
  end

  describe '#perform' do
    context 'without a command' do
      it 'returns an error message' do
        expect(described_class.new.perform)
          .to eq('No command specified.')
      end
    end

    context 'without a role' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net'
        )

        expect(command.perform)
          .to eq('No role specified.')
      end
    end

    context 'without a valid command' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo bar],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net'
        )
        client = instance_double('client')
        repository_tree = instance_double(
          'repository_tree'
        )
        key = instance_double(
          'key',
          name: 'hostname.yml'
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(repository_tree)
          .to receive(:each)
          .and_return(key)

        expect(command.perform)
          .to eq('foo is not a known command.')
      end
    end
  end
end
