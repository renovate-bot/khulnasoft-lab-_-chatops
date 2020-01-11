# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Namespace do
  describe '#perform' do
    context 'without a namespace id' do
      it 'returns an error message' do
        command = described_class.new(%w[], {}, 'GITLAB_TOKEN' => '123')

        expect(command.perform)
          .to match(/You must supply a namespace ID to look up./)

        command.perform
      end
    end
  end

  describe '#submit_namespace_details' do
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
        billable_members_count: 42
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

      command.get_namespace('1234567')
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
        path: 'foobar',
        billable_members_count: 42
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

      command.get_namespace('1234567')
    end
  end
end
