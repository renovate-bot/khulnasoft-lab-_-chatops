# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Feature do
  describe '.perform' do
    it 'supports a --match option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[feature list], { match: 'gitaly' }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --match gitaly])
    end
  end

  describe '.available_subcommands' do
    it 'returns a Markdown list' do
      expect(described_class.available_subcommands).to eq(<<~LIST.strip)
        * get
        * list
        * set
      LIST
    end
  end

  describe '#perform' do
    context 'when using a valid command' do
      it 'executes the command' do
        command = described_class.new(%w[get])

        expect(command).to receive(:get)

        command.perform
      end
    end

    context 'when using an invalid command' do
      it 'returns an error message' do
        command = described_class.new(%w[kittens])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '#unsupported_command' do
    it 'produces a message explaining the command is invalid' do
      command = described_class.new

      expect(command.unsupported_command)
        .to match(/The feature subcommand is invalid/)
    end
  end

  describe '#get' do
    context 'when not specifying a feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[get])

        expect(command.get).to match(/You must specify the name of the feature/)
      end
    end

    context 'when using a non-existing feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123')
        collection = instance_double('collection')

        expect(Chatops::Gitlab::FeatureCollection)
          .to receive(:new)
          .with(token: '123')
          .and_return(collection)

        expect(collection)
          .to receive(:find_by_name)
          .with('foo')
          .and_return(nil)

        expect(command.get).to match('The feature "foo" does not exist.')
      end
    end

    context 'when using a valid feature name' do
      it 'sends the details of the feature to Slack' do
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123')
        collection = instance_double('collection')
        feature = instance_double('feature')

        expect(Chatops::Gitlab::FeatureCollection)
          .to receive(:new)
          .with(token: '123')
          .and_return(collection)

        expect(collection)
          .to receive(:find_by_name)
          .with('foo')
          .and_return(feature)

        expect(command)
          .to receive(:send_feature_details)
          .with(feature: feature)

        command.get
      end
    end
  end

  describe '#set' do
    context 'when not specifying a feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[set])

        expect(command.set).to match(/You must specify the name of the feature/)
      end
    end

    context 'when not specifying a feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo])

        expect(command.set).to match(/You must specify the name of the feature/)
      end
    end

    context 'when specifying an invalid feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo bar])

        expect(command.set).to match(/The value "bar" is invalid/)
      end
    end

    context 'when using valid arguments' do
      it 'updates the feature flag' do
        command = described_class
          .new(%w[set foo 10], {}, 'GITLAB_TOKEN' => '123')

        client = instance_double('client')
        feature = instance_double(
          'feature',
          name: 'foo',
          state: 'conditional',
          gates: [{ 'key' => 'percentage_of_time', 'value' => 10 }]
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:set_feature)
          .with('foo', '10')
          .and_return(feature)

        expect(command).to receive(:send_feature_details).with(
          feature: an_instance_of(Chatops::Gitlab::Feature),
          text: 'The feature flag value has been updated!'
        )

        command.set
      end
    end
  end

  describe '#list' do
    it 'sends the enabled and disabled features to Slack' do
      command = described_class.new(
        %w[list],
        {},
        'GITLAB_TOKEN' => '123',
        'SLACK_TOKEN' => '456',
        'CHAT_CHANNEL' => 'foo'
      )

      message = instance_double('message')

      expect(command)
        .to receive(:attachment_fields_per_state)
        .and_return([[], []])

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(message)

      expect(message).to receive(:send)

      command.list
    end
  end

  describe '#send_feature_details' do
    it 'sends the details of a single feature back to Slack' do
      command = described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => '456')

      feature = Chatops::Gitlab::Feature.new(
        name: 'foo',
        state: 'on',
        gates: [{ 'key' => 'boolean', 'value' => false }]
      )

      message = instance_double('message')

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '123', channel: '456')
        .and_return(message)

      expect(message)
        .to receive(:send)
        .with(a_hash_including(text: 'Hello'))

      command.send_feature_details(feature: feature, text: 'Hello')
    end
  end

  describe '#attachment_fields_per_state' do
    it 'returns attachment fields grouped per state ' do
      command = described_class
        .new([], { match: 'foo' }, 'GITLAB_TOKEN' => '123')

      feature = Chatops::Gitlab::Feature.new(
        name: 'foo',
        state: 'on',
        gates: [{ 'key' => 'boolean', 'value' => false }]
      )

      collection = instance_double('collection', per_state: [[], [feature]])

      expect(Chatops::Gitlab::FeatureCollection)
        .to receive(:new)
        .with(token: '123', match: 'foo')
        .and_return(collection)

      expect(command.attachment_fields_per_state)
        .to eq([[], [feature.to_attachment_field]])
    end
  end
end
