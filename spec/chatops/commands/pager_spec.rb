# frozen_string_literal: true

# Invocation examples:
#
# bundle exec rake coverage

require 'spec_helper'

describe Chatops::Commands::Pager do
  describe '#perform' do
    let(:client) do
      instance_spy(
        Chatops::PagerDuty::ExtendedClient,
        services: double.as_null_object,
        maintenance_windows: double.as_null_object,
        start_maintenance_window: double.as_null_object,
        terminate_maintenance_window: double.as_null_object
      )
    end

    let(:env) do
      {
        'CHAT_CHANNEL' => 'C0123456',
        'PAGERDUTY_TOKEN' => 'pd_token',
        'SLACK_TOKEN' => 'slack_token',
        'GITLAB_USER_LOGIN' => 'tester'
      }
    end

    let(:options) { Chatops::Commands::Pager::DEFAULTS.merge(evironment: 'test') }
    let(:service_name) { 'test_service' }
    let(:service) { [%w[id 12345], %w[type service_reference], ['name', service_name]].to_h }
    let(:services) { [service] }
    let(:mock_now) { '2022-06-06 00:00' }
    let(:start_time) { Time.parse(mock_now) }
    let(:end_time) { (start_time + 60).to_s }
    let(:reason) { format(Chatops::Commands::Pager::MESSAGES[:reason], username: username) }
    let(:username) { 'tester' }
    let(:window) { [['services', services], ['end_time', end_time]].to_h }
    let(:windows) { [window] }

    before do
      allow(Chatops::Slack::Message).to receive(:new)
        .and_return(instance_double('Message', send: true))
    end

    context 'when given the pause action' do
      it 'invokes the pause method' do
        command = described_class.new(%w[pause], options, env)

        expect(command).to receive(:pause).and_return(nil)
        command.perform
      end
    end

    context 'when given the resume action' do
      it 'invokes the resume method' do
        command = described_class.new(%w[resume], options, env)

        expect(command).to receive(:resume).and_return(nil)
        command.perform
      end
    end

    context 'when the pause method is invoked' do
      let(:notice) do
        [
          {
            fallback: 'Pages paused (maintenance window started) for services:',
            pretext: 'Pages paused (maintenance window started) for services:'
          },
          {
            fallback: service_name,
            text: "`#{service_name}`"
          }
        ]
      end

      it 'the ExtendedClient#start_maintenance_window method is invoked' do
        command = described_class.new(%w[pause], options, env)
        allow(command).to receive(:client).and_return(client)
        allow(command).to receive(:start_time).and_return(start_time)
        allow(command).to receive(:parse_duration).and_return(end_time)
        allow(command).to receive(:notice)

        expect(command).to receive(:already_paused?).and_return(false)
        expect(command).to receive(:get_services_by_environment).and_return(services)
        expect(client).to receive(:start_maintenance_window).with(
          services, start_time, end_time, reason
        ).and_return(window)
        command.perform
        expect(command).to have_received(:notice).with(notice)
      end
    end

    context 'when the resume method is invoked' do
      let(:notice) do
        [
          {
            fallback: 'Pager resumed (maintenance window ended) for services:',
            pretext: 'Pager resumed (maintenance window ended) for services:'
          },
          {
            fallback: service_name,
            text: "`#{service_name}`"
          }
        ]
      end

      it 'the ExtendedClient#terminate_maintenance_window method is invoked' do
        command = described_class.new(%w[resume], options, env)
        allow(command).to receive(:client).and_return(client)
        allow(command).to receive(:notice)

        expect(command).to receive(:get_services_by_environment).and_return(services)
        expect(command).to receive(:get_windows_by_services).with(services).and_return(windows)
        expect(command).to receive(:get_active_windows).with(windows).and_return(windows)
        expect(client).to receive(:terminate_maintenance_window).with(window).and_return(window)
        command.perform
        expect(command).to have_received(:notice).with(notice)
      end
    end
  end
  # describe '#perform' do
end
# describe Chatops::Commands::Pager do
