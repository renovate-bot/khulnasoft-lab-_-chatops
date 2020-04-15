# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Broadcast do
  describe '.perform' do
    it 'supports a --target-path, --start and --end option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[hello],
              { target_path: 'baz', start: 'foo', end: 'bar' }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(
        %w[hello --target-path baz --start foo --end bar]
      )
    end
  end

  describe '#perform' do
    context 'when no message is supplied' do
      it 'returns an error message' do
        command = described_class.new

        expect(command.perform).to eq('You must supply a message to set.')
      end
    end

    context 'when no target_path is supplied' do
      it 'returns an error message' do
        command = described_class.new(%w[hello])

        expect(command.perform).to eq('You must specify a --target-path.')
      end
    end

    context 'when a message is supplied' do
      it 'adds a new broadcast message' do
        command = described_class.new(
          %w[hello],
          {
            target_path: 'world',
            start: '2018-01-01 10:00',
            end: '2018-01-01 12:00'
          },
          'GITLAB_TOKEN' => '123'
        )

        client = instance_double('client')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:add_broadcast_message)
          .with(
            'hello',
            target_path: 'world',
            starts_at: Time.new(2018, 1, 1, 10).iso8601,
            ends_at: Time.new(2018, 1, 1, 12).iso8601
          )

        expect(command.perform).to eq('The broadcast message has been added.')
      end
    end
  end

  describe '#parse_time' do
    context 'when no value is provided' do
      it 'returns nil' do
        command = described_class.new

        expect(command.parse_time(:start)).to be_nil
      end
    end

    context 'when an invalid value is provided' do
      it 'raises' do
        command = described_class.new([], start: 'foo')

        expect { command.parse_time(:start) }.to raise_error(ArgumentError)
      end
    end

    context 'when a valid value is provided' do
      it 'returns an ISO 8601 date' do
        command = described_class.new([], start: '2018-01-01 10:00')

        expect(command.parse_time(:start))
          .to eq(Time.new(2018, 1, 1, 10).iso8601)
      end
    end
  end
end
