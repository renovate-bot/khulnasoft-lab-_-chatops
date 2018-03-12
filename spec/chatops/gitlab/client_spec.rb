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

  describe '#set_feature' do
    it 'sets the value of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true' })

      client.set_feature('foo', 'true')
    end
  end
end
