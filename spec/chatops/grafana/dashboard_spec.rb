# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Grafana::Dashboard do
  let(:dashboard) { described_class.new(token: 'hunter2') }
  let(:client) { instance_double('client') }
  let(:success_response) do
    instance_double(
      'response',
      status: instance_double('status', ok?: true),
      body: '{"dashboard": {"id": 1 }}'
    )
  end

  describe '#find_by_uid' do
    before do
      allow(HTTP).to receive(:auth).and_return(client)
    end

    it 'fetches existing dashboard JSON by UID' do
      expect(client)
        .to receive(:get)
        .with('https://dashboards.gitlab.net/api/dashboards/uid/ABC')
        .and_return(success_response)

      result_json = dashboard.find_by_uid('ABC')
      expect(result_json).to eq('dashboard' => { 'id' => 1 })
    end

    it 'raises error if dashboard not found' do
      response = instance_double(
        'response',
        status: instance_double('status', ok?: false),
        body: '{"message": "failed"}'
      )

      expect(client).to receive(:get)
        .with('https://dashboards.gitlab.net/api/dashboards/uid/ABC')
        .and_return(response)

      expect { dashboard.find_by_uid('ABC') }.to raise_error(RuntimeError)
    end
  end
end
