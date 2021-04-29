# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Canary do
  let(:chef_client) { instance_double('chef client') }
  let(:ha_proxy_client) { instance_double('ha_proxy client') }
  let(:events_client) { instance_double('events client') }

  before do
    allow(Chatops::HAProxy::Client)
      .to receive(:new)
      .and_return(ha_proxy_client)
    allow(Chatops::Chef::Client)
      .to receive(:new)
      .and_return(chef_client)
    allow(Chatops::Events::Client)
      .to receive(:new)
      .and_return(events_client)
    allow(chef_client)
      .to receive(:ips_from_role)
      .and_return(['1.1.1.1'])
    allow(chef_client)
      .to receive(:canary_pipeline_url)
      .and_return('https://example.com/some/pipeline/url')
  end

  describe '#perform' do
    def gen_status(state)
      [
        {
          state: state,
          conn: '99',
          server: 'some-cny-server',
          backend: 'some-backend',
          lb_ip: '1.1.1.1',
          weight: '100'
        },
        {
          state: state,
          conn: '99',
          # Canary servers must have the string
          # '-cny-' in the name
          server: 'not-a-canary-server',
          backend: 'some-backend',
          lb_ip: '1.1.1.1',
          weight: '100'
        }
      ]
    end

    context 'when there is a single cny server' do
      it 'describes a single server with no options' do
        command = described_class.new(
          [], {},
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
        expect(ha_proxy_client).not_to receive(:set_server_state)
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('UP'))

        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            _Use `/chatops run canary --help` to list canary commands_
            Displaying the current canary status:
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 UP:1
            ```
            *UP*: some-cny-server
          CNY_RESULT
        )
      end
    end

    context 'when state is set to drain' do
      it 'sets state to drain' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            server_stats: gen_status(
              'DRAIN'
            ).select { |s| s[:server] == 'some-cny-server' },
            state: 'drain'
          )
        expect(events_client).to receive(:send_event)
          .once.with('Canary set to drain')
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('DRAIN'))
        command = described_class.new(
          [], { drain: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
        expect(command).to receive(:canary_active_deployment?)
          .and_return(false)

        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 DRAIN:1
            ```
            *DRAIN*: some-cny-server
          CNY_RESULT
        )
      end
    end

    context 'when state is set to maint' do
      it 'sets state to maint' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            server_stats: gen_status(
              'MAINT'
            ).select { |s| s[:server] == 'some-cny-server' },
            state: 'maint'
          )
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('MAINT'))
        expect(events_client).to receive(:send_event)
          .once.with('Canary set to maint')
        command = described_class.new(
          [], { maint: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
        expect(command).to receive(:canary_active_deployment?)
          .and_return(false)
        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 MAINT:1
            ```
            *MAINT*: some-cny-server
          CNY_RESULT
        )
      end
    end

    shared_examples 'enabling the canary' do
      it 'sets state to ready' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            server_stats: gen_status(
              'UP'
            ).select { |s| s[:server] == 'some-cny-server' },
            state: 'ready'
          )
        expect(events_client).to receive(:send_event)
          .once.with('Canary set to ready')
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('UP'))
        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 UP:1
            ```
            *UP*: some-cny-server
          CNY_RESULT
        )
        expect(command).not_to receive(:canary_active_deployment?)
      end
    end

    context 'when state is set to ready' do
      let(:command) do
        described_class.new(
          [], { ready: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
      end

      it_behaves_like 'enabling the canary'
    end

    context 'when there is an active deployment' do
      let(:command) do
        described_class.new(
          [], { disable: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
      end

      before do
        allow(command).to receive(:canary_active_deployment?).twice
          .and_return(true)
      end

      it 'returns an error' do
        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            Unable to set canary state because there is a <https://example.com/some/pipeline/url|canary deploy in progress>.
            Draining canary while there is a deploy will cause errors for users connecting to canary hosts.
            If you are sure you want to proceed anyway, use the `--ignore-deployment-check` option.
          CNY_RESULT
        )
      end
    end

    context 'when state is set to enable' do
      let(:command) do
        described_class.new(
          [], { enable: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
      end

      it_behaves_like 'enabling the canary'
    end

    shared_examples 'disabling canary' do
      it 'sets state to drain and then maint' do
        expect(command).to receive(:sleep).once.with(60)
        expect(events_client).to receive(:send_event)
          .once.with('Canary set to drain')
        expect(events_client).to receive(:send_event)
          .once.with('Canary set to maint')

        %w[drain maint].each do |state|
          expect(ha_proxy_client).to receive(:set_server_state)
            .once.ordered.with(
              server_stats: gen_status(
                state.upcase
              ).select { |s| s[:server] == 'some-cny-server' },
              state: state
            )
        end

        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 MAINT:1
            ```
            *MAINT*: some-cny-server
          CNY_RESULT
        )
      end
    end

    context 'when state is set to disable' do
      let(:command) do
        described_class.new(
          [], { disable: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
      end

      before do
        allow(command).to receive(:canary_active_deployment?).twice
          .and_return(false)
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(
            gen_status('DRAIN'),
            gen_status('MAINT')
          )
      end

      it_behaves_like 'disabling canary'
    end

    context 'when state is set to disable during an active deployment with override' do
      let(:command) do
        described_class.new(
          [], { disable: true, ignore_deployment_check: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
      end

      before do
        allow(command).to receive(:canary_active_deployment?).twice
          .and_return(true)
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(
            gen_status('DRAIN'),
            gen_status('MAINT')
          )
      end

      it_behaves_like 'disabling canary'
    end
  end
end
