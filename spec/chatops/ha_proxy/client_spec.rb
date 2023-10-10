# frozen_string_literal: true

require 'spec_helper'

describe Chatops::HAProxy::Client do
  let(:client) do
    described_class.new(lbs: ['1.1.1.1', '2.2.2.2'])
  end
  let(:sock) { instance_spy(TCPSocket) }

  before do
    allow(TCPSocket)
      .to receive(:new)
      .and_return(sock)
  end

  def lb_lines
    [
      '# lb 1',
      'api,api-01-sv-gstg,0,0,7,14,,4536,4080349,1964692' \
      ',,0,,0,0,0,0,UP,100,1,0,0,0,5  155,0,,1,10,1,,4536,,' \
      '2,4,,7,L7OK,200,4,0,866,0,3663,0,0,0,,,,0,0,,,,,0,OK,' \
      ',0,0,8368,8693,',
      'https_git,git-cny-01-sv-gstg,0,0,0,0,,0,0,0,,0,,0,0,0,0,UP,' \
      '0,1,0,0,0,5155,0,,1,12,4,,0,,2,0,,0,L7OK,200,5,0,0,0,0,0,0,' \
      '0,,,,0,0,,,,,-1,OK,,0,0,0,0,',
      nil,
      '# lb 2',
      'api,api-01-sv-gstg,0,0,7,14,,4536,4080349,1964692,,0,,0,0,0,0,' \
      'UP,100,1,0,0,0,5  155,0,,1,10,1,,4536,,2,4,,7,L7OK,200,4,0,866,' \
      '0,3663,0,0,0,,,,0,0,,,,,0,OK,,0,0,8368,8693,',
      nil
    ]
  end

  def server_stats
    [
      {
        backend: 'api',
        conn: '7',
        lb_ip: '1.1.1.1',
        server: 'api-01-sv-gstg',
        state: 'UP',
        weight: '100'
      },
      {
        backend: 'https_git',
        conn: '0',
        lb_ip: '1.1.1.1',
        server: 'git-cny-01-sv-gstg',
        state: 'UP',
        weight: '0'
      },
      {
        backend: 'api',
        conn: '7',
        lb_ip: '2.2.2.2',
        server: 'api-01-sv-gstg',
        state: 'UP',
        weight: '100'
      }
    ]
  end

  describe '#set_server_state' do
    it 'sets the server state for servers' do
      client.set_server_state(
        server_stats: server_stats,
        state: Chatops::HAProxy::Client::DRAIN_STATE
      )

      expect(sock)
        .to have_received(:write).with(
          "set server api/api-01-sv-gstg state DRAIN\n"
        ).twice
      expect(sock)
        .to have_received(:write).with(
          "set server https_git/git-cny-01-sv-gstg state DRAIN\n"
        ).once
    end
  end

  describe '#server_stats' do
    it 'fetches lb server stats' do
      allow(sock)
        .to receive(:gets).and_return(*lb_lines)
      expect(client.server_stats).to eq(server_stats)

      expect(sock)
        .to have_received(:write).twice.with("show stat\n")
      expect(sock)
        .to have_received(:close).twice
    end
  end

  context 'when there is a connection error' do
    it 'retries lb server stats' do
      allow(sock)
        .to receive(:gets).and_raise(Errno::ECONNRESET)
      allow(client).to receive(:sleep)
      expect($stdout).to receive(:puts)
        .with('Giving up on LB 1.1.1.1 after 10 retries')

      expect { client.server_stats }.to raise_error(Errno::ECONNRESET)

      expect(sock)
        .to have_received(:write).exactly(10).times.with("show stat\n")
      expect(sock)
        .not_to have_received(:close)
    end
  end
end
