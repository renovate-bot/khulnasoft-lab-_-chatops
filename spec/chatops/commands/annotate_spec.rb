# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Annotate do
  describe '#perform' do
    let(:options) do
      {
        'GITLAB_TOKEN' => '123',
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_USER_LOGIN' => 'jane_doe'
      }
    end
    let(:annotation) { 'My annotation' }
    let(:grafana_annotate) { instance_double('grafana_annotate') }

    before do
      allow(Chatops::Grafana::Annotate)
        .to receive(:new)
        .with(token: 'some-grafana-token')
        .and_return(grafana_annotate)
    end

    context 'when sending non-empty string' do
      it 'appends the username and posts an annotation' do
        command = described_class.new([annotation], {}, options)

        expect(grafana_annotate)
          .to receive(:annotate!)
          .with('My annotation (by jane_doe)', tags: ['gprd'])

        command.perform
      end
    end

    context 'when sending empty string' do
      it 'fails fast with an error' do
        command = described_class.new([], {}, options)

        expect(grafana_annotate).not_to receive(:annotate!)

        expect(command.perform).not_to be_empty
      end
    end
  end
end
