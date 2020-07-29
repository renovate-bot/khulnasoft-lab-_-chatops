# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Database do
  describe '#trigger_token' do
    context 'when the DATABASE_TRIGGER_TOKEN variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the DATABASE_TRIGGER_TOKEN variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class.new([], {}, 'DATABASE_TRIGGER_TOKEN' => 'foo')

        expect(command.trigger_token).to eq('foo')
      end
    end
  end

  describe '#trigger_project' do
    context 'when the DATABASE_TRIGGER_PROJECT variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the DATABASE_TRIGGER_PROJECT variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class
          .new([], {}, 'DATABASE_TRIGGER_PROJECT' => 'foo')

        expect(command.trigger_project).to eq('foo')
      end
    end
  end

  describe '#environment' do
    it 'returns gstg by default' do
      expect(described_class.new.environment).to eq('gstg')
    end

    it 'returns gprd when the --production option is set' do
      command = described_class.new([], production: true)

      expect(command.environment).to eq('gprd')
    end
  end

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
  end

  describe '#perform' do
    context 'without a command' do
      it 'returns an error message' do
        command = described_class.new(
          %w[],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'DATABASE_TRIGGER_HOST' => 'ops.gitlab.net'
        )

        expect(command.perform)
          .to eq(':database: No command specified.')
      end
    end

    context 'with a list option' do
      it 'returns a list of commands' do
        command = described_class.new(
          %w[foo bar],
          { list: true },
          'GITLAB_OPS_TOKEN' => '12345',
          'DATABASE_TRIGGER_HOST' => 'ops.gitlab.net'
        )
        client = instance_double('client')
        repository_tree = [
          Gitlab::ObjectifiedHash.new(name: 'README.md'),
          Gitlab::ObjectifiedHash.new(name: 'switchover_primary.yml')
        ]

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(<<~HELP.chomp)
            :database: The following commands are available:

            * `switchover_primary`

            For more information run `database --help`.
          HELP
      end
    end

    context 'without a valid command' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo bar],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'DATABASE_TRIGGER_HOST' => 'ops.gitlab.net'
        )
        client = instance_double('client')
        repository_tree = [
          Gitlab::ObjectifiedHash.new(name: 'README.md'),
          Gitlab::ObjectifiedHash.new(name: 'switchover_primary.yml')
        ]

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(<<~HELP.chomp)
            :database: The provided command is invalid. The following commands are available:

            * `switchover_primary`

            For more information run `database --help`.
          HELP
      end
    end

    context 'with a valid command' do
      def trigger_args
        [
          '777',
          'florb',
          :master,
          'CMD': 'foo',
          'DB_OPS_ENV': 'gstg'
        ]
      end

      it 'returns success' do
        command = described_class.new(
          %w[foo bar],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'DATABASE_TRIGGER_HOST' => 'ops.gitlab.net',
          'DATABASE_TRIGGER_PROJECT' => '777',
          'DATABASE_TRIGGER_TOKEN' => 'florb'
        )
        client = instance_double('client')
        repository_tree = [Gitlab::ObjectifiedHash.new(name: 'foo.yml')]
        response = instance_double('response', web_url: 'bar')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:run_trigger)
          .with(*trigger_args)
          .and_return(response)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(':database: Command `foo` was issued in `gstg`: <bar>')
      end
    end

    context 'when the request is invalid' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo bar],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'DATABASE_TRIGGER_HOST' => 'ops.gitlab.net',
          'DATABASE_TRIGGER_PROJECT' => '777',
          'DATABASE_TRIGGER_TOKEN' => 'florb'
        )
        client = instance_double('client')
        repository_tree = [Gitlab::ObjectifiedHash.new(name: 'foo.yml')]

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:run_trigger)
          .and_raise(StandardError.new('oops'))

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(':database: The command could not be run: oops')
      end
    end
  end
end
