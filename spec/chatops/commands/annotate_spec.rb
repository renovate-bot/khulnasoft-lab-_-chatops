# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Annotate do
  describe '#perform' do
    let(:settings) do
      {
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_USER_LOGIN' => 'jane_doe',
        'SLACK_TOKEN' => 'abc',
        'CHAT_CHANNEL' => 'chan'
      }
    end
    let(:grafana_annotate) { instance_double('Grafana::Annotate') }
    let(:grafana_dashboard) { instance_double('Grafana::Dashboard') }
    let(:slack_message) { instance_double('Slack::Message') }
    let(:success_response) do
      {
        'message' => 'Annotation added',
        'id' => 1
      }
    end

    let(:dashboard_response) do
      {
        'dashboard' => { 'id' => 42 }
      }
    end

    before do
      allow(Chatops::Grafana::Annotate)
        .to receive(:new)
        .with(token: 'some-grafana-token')
        .and_return(grafana_annotate)

      allow(Chatops::Grafana::Dashboard)
        .to receive(:new)
        .with(token: 'some-grafana-token')
        .and_return(grafana_dashboard)

      allow(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: 'abc', channel: 'chan')
        .and_return(slack_message)
    end

    context 'when sending non-empty string' do
      it 'appends the username and posts an annotation to given dashboards' do
        options = { dashboard_uids: %w[A B] }
        command = described_class.new(%w[my annotation text], options, settings)

        expect(grafana_dashboard)
          .to receive(:find_by_uid)
          .twice
          .and_return(dashboard_response)

        expect(grafana_annotate)
          .to receive(:annotate!)
          .twice
          .with(
            'my annotation text (<a href="https://gitlab.com/jane_doe">@jane_doe</a>)', # rubocop:disable Metrics/LineLength
            tags: ['user-annotation', 'gprd'], dashboard_id: 42
          )
          .and_return(success_response)

        expect(slack_message).to receive(:send)

        command.perform
      end

      it 'removes trailing whitespace' do
        options = { dashboard_uids: %w[A B] }
        command = described_class.new(
          [' ', 'my', 'annotation', 'text', ' '], options, settings
        )

        expect(grafana_dashboard)
          .to receive(:find_by_uid)
          .twice
          .and_return(dashboard_response)
        expect(grafana_annotate)
          .to receive(:annotate!)
          .twice
          .with(
            'my annotation text (<a href="https://gitlab.com/jane_doe">@jane_doe</a>)', # rubocop:disable Metrics/LineLength
            tags: ['user-annotation', 'gprd'], dashboard_id: 42
          )
          .and_return(success_response)

        expect(slack_message).to receive(:send)

        command.perform
      end
    end

    context 'when sending empty string' do
      it 'fails fast with an error' do
        command = described_class.new([], {}, settings)

        expect(grafana_annotate).not_to receive(:annotate!)
        expect(slack_message).not_to receive(:send)

        expect(command.perform).not_to be_empty
      end
    end
  end
end
