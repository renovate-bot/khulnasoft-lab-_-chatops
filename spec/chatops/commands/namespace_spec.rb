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

    # context 'when passed a namespace ID' do
    #   it 'tries to look it up' do
    #     command = described_class.new(%w[namespace 1234567], {}, 'GITLAB_TOKEN' => '123')
    #     client = instance_double('client')
    #     namespace = instance_double('namespace')
    #
    #     expect(Chatops::Gitlab::Client)
    #       .to receive(:new)
    #       .with(token: '123')
    #       .and_return(client)
    #
    #     expect(client)
    #       .to receive(:find_namespace)
    #       .with('1234567')
    #       .and_return(namespace)
    #
    #     expect(command)
    #       .to receive(:submit_namespace_details)
    #       .with(namespace)
    #
    #     command.perform
    #   end
    # end
  end

  describe '#submit_namespace_details' do
    context 'when using a valid namespace id' do
      it 'sends the details of the namespace to Slack' do
        command = described_class.new(%w[1234567], {}, 'CHAT_CHANNEL' => 'test_channel', 'SLACK_TOKEN' => '123')
        namespace = instance_double('namespace')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(namespace)

        expect(command.submit_namespace_details(namespace))
          .to receive(:submit_namespace_details)
          .with(namespace: namespace)

        command.submit_namespace_details(namespace)
      end
    end
  end
end
