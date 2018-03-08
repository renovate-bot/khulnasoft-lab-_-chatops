# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Grafana::Graph do
  let(:graph) do
    described_class.new(
      dashboard: 'transactions',
      panel_id: 2,
      token: 'hunter2',
      variables: { from: 1, to: 10 }
    )
  end

  describe '#url' do
    it 'returns the URL of a graph' do
      expect(graph.url).to eq(
        described_class::HOST +
          '/render/dashboard-solo/db/transactions?panelId=2&orgId=1' \
          '&height=500&width=1000&from=1&to=10'
      )
    end
  end

  describe '#download' do
    context 'when Grafana responds with an error' do
      it 'raises DownloadError' do
        client = instance_double('client')
        response = instance_double('response', status: 404)

        expect(HTTP)
          .to receive(:auth)
          .and_return(client)

        expect(client)
          .to receive(:get)
          .with(graph.url)
          .and_return(response)

        expect { graph.download }.to raise_error(described_class::DownloadError)
      end
    end

    context 'when Grafana responds with an HTTP 200 OK' do
      it 'downloads a graph' do
        client = instance_double('client')
        response = instance_double('response', status: 200, body: 'hello')

        expect(HTTP)
          .to receive(:auth)
          .and_return(client)

        expect(client)
          .to receive(:get)
          .with(graph.url)
          .and_return(response)

        expect(Tempfile)
          .to receive(:new)
          .with('.png')
          .and_return(StringIO.new)

        image = graph.download

        expect(image.read).to eq('hello')
      end
    end
  end
end
