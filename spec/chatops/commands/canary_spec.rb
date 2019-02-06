# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Canary do
  let(:chef_client) { instance_double('chef client') }
  let(:ha_proxy_client) { instance_double('ha_proxy client') }

  before do
    allow(Chatops::HAProxy::Client)
      .to receive(:new)
      .and_return(ha_proxy_client)
    allow(Chatops::Chef::Client)
      .to receive(:new)
      .and_return(chef_client)
    allow(chef_client)
      .to receive(:hostnames_from_role)
      .and_return(['some-cny-server'])
    allow(chef_client)
      .to receive(:ips_from_role)
      .and_return([])
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
          server: 'not-a-cny-server',
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
      it 'stets state to drain' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            backend: nil,
            servers: ['some-cny-server'],
            state: 'drain'
          )
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('DRAIN'))
        command = described_class.new(
          [], { drain: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
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
      it 'stets state to maint' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            backend: nil,
            servers: ['some-cny-server'],
            state: 'maint'
          )
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('MAINT'))
        command = described_class.new(
          [], { maint: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
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

    context 'when state is set to ready' do
      it 'stets state to ready' do
        expect(ha_proxy_client).to receive(:set_server_state)
          .with(
            backend: nil,
            servers: ['some-cny-server'],
            state: 'ready'
          )
        allow(ha_proxy_client)
          .to receive(:server_stats)
          .and_return(gen_status('UP'))
        command = described_class.new(
          [], { ready: true },
          'CHEF_USERNAME' => 'fake-user',
          'CHEF_PEM_KEY' => 'fake-pem'
        )
        expect(command.perform).to eq(
          <<~CNY_RESULT.chomp
            :canary: :canary: :canary:
            ```
            some-backend        : conn:99 UP:1
            ```
            *UP*: some-cny-server
          CNY_RESULT
        )
      end
    end
  end
end
