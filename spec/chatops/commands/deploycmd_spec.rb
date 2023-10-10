# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Deploycmd do
  describe '#trigger_token' do
    context 'when the COMMAND_TRIGGER_TOKEN variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the COMMAND_TRIGGER_TOKEN variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class.new([], {}, 'COMMAND_TRIGGER_TOKEN' => 'foo')

        expect(command.trigger_token).to eq('foo')
      end
    end
  end

  describe '#trigger_project' do
    context 'when the COMMAND_TRIGGER_PROJECT variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the COMMAND_TRIGGER_PROJECT variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class
          .new([], {}, 'COMMAND_TRIGGER_PROJECT' => 'foo')

        expect(command.trigger_project).to eq('foo')
      end
    end
  end

  describe '#environment' do
    it 'returns an error when no environment is specified' do
      expect { described_class.new.environment }.to raise_error(
        StandardError, /You must pass an environment name/
      )
    end

    it 'returns gstg when the --staging option is set' do
      command = described_class.new([], staging: true)

      expect(command.environment).to eq('gstg')
    end

    it 'returns gprd when the --production option is set' do
      command = described_class.new([], production: true)

      expect(command.environment).to eq('gprd')
    end

    it 'returns pre when the --pre option is set' do
      command = described_class.new([], pre: true)

      expect(command.environment).to eq('pre')
    end

    it 'returns gprd-cny when the --production and --canary options are set' do
      command = described_class.new([], production: true, canary: true)

      expect(command.environment).to eq('gprd-cny')
    end

    it 'returns gstg-cny when the --canary option is set' do
      command = described_class.new([], staging: true, canary: true)

      expect(command.environment).to eq('gstg-cny')
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

    it 'supports a --staging option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(staging: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--staging])
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
        command = described_class.new(
          %w[],
          {},
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net'
        )

        expect(command.perform)
          .to eq(':unicorn_face: No command specified.')
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
          .to eq(':unicorn_face: No role specified.')
      end
    end

    context 'with a list option' do
      it 'returns a list of commands' do
        command = described_class.new(
          %w[foo bar],
          { list: true },
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net'
        )
        client = instance_double('client')
        repository_tree = [
          Gitlab::ObjectifiedHash.new(name: 'README.md'),
          Gitlab::ObjectifiedHash.new(name: 'hostname.yml')
        ]

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(':unicorn_face: The following commands are'\
            " available:\n\n* `hostname`\n\nFor more information"\
            ' run `deploycmd --help`.')
      end
    end

    context 'without a valid command' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo bar],
          { staging: true },
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net'
        )
        client = instance_double('client')
        repository_tree = [
          Gitlab::ObjectifiedHash.new(name: 'README.md'),
          Gitlab::ObjectifiedHash.new(name: 'hostname.yml')
        ]

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(host: 'ops.gitlab.net', token: '12345')
          .and_return(client)

        expect(client)
          .to receive(:repository_tree)
          .and_return(repository_tree)

        expect(command.perform)
          .to eq(':unicorn_face: The provided command is invalid.'\
            " The following commands are available:\n\n* `hostname`\n\nFor"\
            ' more information run `deploycmd --help`.')
      end
    end

    context 'with a valid command' do
      def trigger_args
        [
          '777',
          'florb',
          :master,
          {
            CHECKMODE: 'true',
            CMD: 'foo',
            CURRENT_DEPLOY_ENVIRONMENT: 'gstg',
            GITLAB_ROLES: 'bar'
          }
        ]
      end

      it 'returns success' do
        command = described_class.new(
          %w[foo bar],
          { staging: true },
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net',
          'COMMAND_TRIGGER_PROJECT' => '777',
          'COMMAND_TRIGGER_TOKEN' => 'florb'
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
          .to eq(':unicorn_face: Command `foo` was issued ' \
            'to `bar` in `gstg`: <bar>')
      end
    end

    context 'when the request is invalid' do
      it 'returns an error message' do
        command = described_class.new(
          %w[foo bar],
          { staging: true },
          'GITLAB_OPS_TOKEN' => '12345',
          'COMMAND_TRIGGER_HOST' => 'ops.gitlab.net',
          'COMMAND_TRIGGER_PROJECT' => '777',
          'COMMAND_TRIGGER_TOKEN' => 'florb'
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
          .to eq(':unicorn_face: The command could not be run: oops')
      end
    end
  end
end
