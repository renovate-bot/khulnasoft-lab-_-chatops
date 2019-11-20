# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Grafana::Annotate do
  let(:graph) { described_class.new(token: 'hunter2') }

  describe '#invoke!' do
    it 'posts a successful annotation' do
      client = instance_double('client')
      response = instance_double(
        'response',
        status: instance_double('status', ok?: true),
        body_to_s: 'ok'
      )

      expect(HTTP)
        .to receive(:auth)
        .and_return(client)

      expect(client)
        .to receive(:post)
        .with(
          'https://dashboards.gitlab.net/api/annotations',
          json: {
            text: 'some annotation',
            tags: ['some-tag', 'another-tag']
          }
        )
        .and_return(response)

      expect(
        graph.annotate!(
          'some annotation',
          tags: ['some-tag', 'another-tag']
        )
      ).to eq('ok')
    end

    it 'fails to post an annotation' do
      client = instance_double('client')
      response = instance_double(
        'response',
        status: instance_double('status', ok?: false),
        body_to_s: 'not ok'
      )

      expect(HTTP)
        .to receive(:auth)
        .exactly(3).times
        .and_return(client)

      expect(client)
        .to receive(:post)
        .exactly(3).times
        .with(
          'https://dashboards.gitlab.net/api/annotations',
          json: {
            text: 'some annotation',
            tags: ['some-tag', 'another-tag']
          }
        )
        .and_return(response)

      allow(graph)
        .to receive(:sleep)

      expect do
        graph.annotate!(
          'some annotation',
          tags: ['some-tag', 'another-tag']
        )
      end.to raise_error(RuntimeError)
    end
  end
end
