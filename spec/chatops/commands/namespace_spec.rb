# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Namespace do
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
        command = described_class.new(%w[find alice])

        expect(command)
          .to receive(:find)
          .with('alice')

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[foo])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* find')
    end
  end

  describe '#find' do
    let(:client) { instance_double('client') }
    let(:namespace1) do
      instance_double(
        'namespace',
        id: '1234567',
        name: 'testname',
        kind: 'group',
        path: 'foobar',
        full_path: 'root/foobar',
        billable_members_count: 42,
        seats_in_use: 2,
        plan: 'default',
        trial: false,
        trial_ends_on: '',
        extra_shared_runners_minutes_limit: 2000,
        root_repository_size: 8675,
        projects_count: 309
      )
    end

    let(:namespace2) do
      instance_double(
        'namespace',
        id: '1234568',
        name: 'testname',
        kind: 'group',
        path: 'foobar',
        full_path: 'root/foobar',
        billable_members_count: 42,
        seats_in_use: 2,
        plan: 'default',
        trial: false,
        trial_ends_on: '',
        extra_shared_runners_minutes_limit: 2000,
        root_repository_size: 8675,
        projects_count: 309
      )
    end

    context 'without a namespace' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.find).to eq('You must supply one or more namespace paths or IDs.')
      end
    end

    context 'with a single valid namespace' do
      it 'sends the details of the namespace to Slack' do
        command = described_class.new(
          %w[1234567],
          {},
          'GITLAB_TOKEN' => '1234',
          'CHAT_CHANNEL' => 'test_channel',
          'SLACK_TOKEN' => '123'
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '1234')
          .and_return(client)

        expect(client)
          .to receive(:find_namespace)
          .with('1234567')
          .and_return(namespace1)

        expect(command)
          .to receive(:submit_namespace_details)
          .with(namespace1)

        expect(command.find('1234567')).to eq(nil)
      end
    end

    context 'with a multiple valid namespaces' do
      it 'sends the details of the namespaces to Slack' do
        command = described_class.new(
          %w[1234567 1234568],
          {},
          'GITLAB_TOKEN' => '1234',
          'CHAT_CHANNEL' => 'test_channel',
          'SLACK_TOKEN' => '123'
        )

        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '1234')
          .and_return(client)

        expect(client)
          .to receive(:find_namespace)
          .with('1234567')
          .and_return(namespace1)

        expect(client)
          .to receive(:find_namespace)
          .with('1234568')
          .and_return(namespace2)

        expect(command)
          .to receive(:submit_namespace_details)
          .with(namespace1)

        expect(command)
          .to receive(:submit_namespace_details)
          .with(namespace2)

        expect(command.find('1234567', '1234568')).to eq(nil)
      end
    end

    context 'with a valid and invalid namespace' do
      it 'sends the details of the valid namespace to Slack' do
        command = described_class.new(
          %w[1234567],
          {},
          'GITLAB_TOKEN' => '1234',
          'CHAT_CHANNEL' => 'test_channel',
          'SLACK_TOKEN' => '123'
        )

        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '1234')
          .and_return(client)

        expect(client)
          .to receive(:find_namespace)
          .with('1234567')
          .and_return(namespace1)

        expect(client)
          .to receive(:find_namespace)
          .with('1234569')
          .and_raise(gitlab_error(:NotFound))

        expect(client)
          .to receive(:find_namespace)
          .with('invalid2')
          .and_raise(gitlab_error(:NotFound))

        expect(command)
          .to receive(:submit_namespace_details)
          .with(namespace1)

        expect(command.find('1234567', '1234569', 'invalid2')).to eq(
          "No namespace could be found for \"1234569\".\n" \
          'No namespace could be found for "invalid2".'
        )
      end
    end

    context 'with too many arguments' do
      it 'returns an error message' do
        command = described_class.new(%w[find])
        ids = %w[1 2 3 4 5 6]

        expect(command.find(*ids)).to eq('Too many namespaces provided (max 5).')
      end
    end
  end

  describe '#namespace_not_found_error' do
    it 'reports no namespace could be found.' do
      command = described_class.new(
        %w[1234567],
        {},
        'GITLAB_TOKEN' => '1234',
        'CHAT_CHANNEL' => 'test_channel',
        'SLACK_TOKEN' => '123'
      )
      client = instance_double('client')
      namespace = instance_double(
        'namespace',
        id: '1234567',
        name: 'testname',
        kind: 'group',
        path: 'foobar'
      )

      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '1234')
        .and_return(client)

      expect(client)
        .to receive(:find_namespace)
        .with('1234567')
        .and_return(namespace)

      expect(command)
        .to receive(:submit_namespace_details)
        .with(namespace)

      command.find('1234567')
    end
  end
end
