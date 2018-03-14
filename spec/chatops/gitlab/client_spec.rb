# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Client do
  let(:client) { described_class.new(token: '123', endpoint: 'localhost') }

  describe '#features' do
    it 'returns the feature flags' do
      collection = instance_double('collection')

      expect(client.internal_client)
        .to receive(:get)
        .with('/features')
        .and_return(collection)

      expect(collection)
        .to receive(:auto_paginate)

      client.features
    end
  end

  describe '#find_user' do
    context 'when a user could be found' do
      it 'returns the user' do
        user = instance_double('user')

        expect(client.internal_client)
          .to receive(:users)
          .with(username: 'alice')
          .and_return([user])

        expect(client.find_user('alice')).to eq(user)
      end
    end

    context 'when a user could not be found' do
      it 'returns nil' do
        expect(client.internal_client)
          .to receive(:users)
          .with(username: 'alice')
          .and_return([])

        expect(client.find_user('alice')).to be_nil
      end
    end
  end

  describe '#set_feature' do
    it 'sets the value of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true' })

      client.set_feature('foo', 'true')
    end
  end

  describe '#add_broadcast_message' do
    context 'without a start and end date' do
      it 'adds a broadcast message without an explicit start and end date' do
        expect(client.internal_client)
          .to receive(:post)
          .with('/broadcast_messages', body: { message: 'hello' })

        client.add_broadcast_message('hello')
      end
    end

    context 'with a start and end date' do
      it 'adds a broadcast message with the given start and end date' do
        expect(client.internal_client)
          .to receive(:post)
          .with(
            '/broadcast_messages',
            body: { message: 'hello', starts_at: 'foo', ends_at: 'bar' }
          )

        client.add_broadcast_message('hello', starts_at: 'foo', ends_at: 'bar')
      end
    end
  end
end
