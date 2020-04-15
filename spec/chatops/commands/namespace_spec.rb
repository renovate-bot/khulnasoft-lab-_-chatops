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
    context 'without a namesapce' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.find).to eq('You must supply a namespace path or ID.')
      end
    end

    context 'with a valid namespace' do
      it 'sends the details of the namespace to Slack' do
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
          path: 'foobar',
          billable_members_count: 42,
          plan: 'default',
          extra_shared_runners_minutes_limit: 2000
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
