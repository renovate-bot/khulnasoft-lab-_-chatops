# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::FeatureCollection do
  let(:feature_definition) do
    {
      name: 'my_user_feature',
      introduced_by_url: 'https://foo.bar/project-org/project/-/merge_requests/1',
      rollout_issue_url: 'https://foo.bar/project-org/project/-/issues/2',
      group: 'group::ci',
      type: 'development',
      default_enabled: false
    }
  end

  describe '#find_by_name' do
    context 'when the feature does not exist' do
      it 'returns nil' do
        collection = described_class.new(token: '123')

        expect(collection)
          .to receive(:raw_features)
          .and_return([])

        expect(collection.find_by_name('foo')).to be_nil
      end
    end

    context 'when the feature exists' do
      it 'returns the feature' do
        collection = described_class.new(token: '123')

        raw_feature = instance_double(
          'feature',
          name: 'foo',
          state: 'on',
          gates: [],
          definition: feature_definition
        )

        expect(collection)
          .to receive(:raw_features)
          .and_return([raw_feature])

        expect(collection.find_by_name('foo'))
          .to be_an_instance_of(Chatops::Gitlab::Feature)
      end
    end
  end

  describe '#per_state' do
    it 'returns the features grouped per state' do
      collection = described_class.new(token: '123')

      features = [
        instance_double(
          'feature b',
          name: 'b',
          state: 'on',
          gates: [], definition: feature_definition
        ),
        instance_double(
          'feature a',
          name: 'a',
          state: 'on',
          gates: [],
          definition: feature_definition
        ),
        instance_double(
          'feature c',
          name: 'c',
          state: 'off',
          gates: [],
          definition: feature_definition
        )
      ]

      expect(collection)
        .to receive(:raw_features)
        .and_return(features)

      enabled, disabled = collection.per_state

      expect(enabled[0].name).to eq('a')
      expect(enabled[1].name).to eq('b')
      expect(disabled[0].name).to eq('c')
    end
  end

  describe '#each' do
    it 'yields a Chatops::Gitlab::Feature for every feature' do
      collection = described_class.new(token: '123')

      features = [
        instance_double(
          'feature a',
          name: 'a',
          state: 'on',
          gates: [],
          definition: feature_definition
        )
      ]

      expect(collection)
        .to receive(:raw_features)
        .and_return(features)

      expect { |b| collection.each(&b) }
        .to yield_with_args(an_instance_of(Chatops::Gitlab::Feature))
    end
  end
end
