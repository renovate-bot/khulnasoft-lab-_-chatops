# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Grafana::Annotate do
  let(:annotate) { described_class.new(token: 'hunter2') }
  let(:client) { instance_double('client') }
  let(:success_response) do
    instance_double(
      'response',
      status: instance_double('status', ok?: true),
      body: '{"message": "Annotation added", "id": 1}'
    )
  end

  describe '#annotate!' do
    before do
      allow(HTTP).to receive(:auth).and_return(client)
      allow(annotate).to receive(:sleep)
    end

    it 'posts a successful annotation and returns the JSON' do
      expect(client)
        .to receive(:post)
        .with(
          'https://dashboards.gitlab.net/api/annotations',
          json: {
            text: 'some annotation',
            tags: ['some-tag', 'another-tag']
          }
        )
        .and_return(success_response)

      result_json = annotate.annotate!(
        'some annotation',
        tags: ['some-tag', 'another-tag']
      )
      expect(result_json).to eq('message' => 'Annotation added', 'id' => 1)
    end

    it 'posts a successful annotation for a given dashboard' do
      expect(client)
        .to receive(:post)
        .with(
          'https://dashboards.gitlab.net/api/annotations',
          json: {
            text: 'some annotation',
            tags: ['some-tag', 'another-tag'],
            dashboardId: 42
          }
        )
        .and_return(success_response)

      result_json = annotate.annotate!(
        'some annotation',
        tags: ['some-tag', 'another-tag'],
        dashboard_id: 42
      )

      expect(result_json).to eq('message' => 'Annotation added', 'id' => 1)
    end

    it 'fails to post an annotation' do
      response = instance_double(
        'response',
        status: instance_double('status', ok?: false),
        body: '{"message": "failed"}'
      )

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

      expect do
        annotate.annotate!(
          'some annotation',
          tags: ['some-tag', 'another-tag']
        )
      end.to raise_error(RuntimeError)
    end
  end
end
