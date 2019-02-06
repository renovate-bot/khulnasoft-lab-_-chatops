# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Chef::Client do
  let(:client) do
    described_class.new('fake_user',
                        'fake_key',
                        'https://example.com')
  end
  let(:query_result) { instance_double('chef search results') }
  let(:node_with_valid_client) do
    { 'hostname' => 'herp', 'ipaddress' => '1.1.1.1' }
  end

  before do
    allow(query_result)
      .to receive(:search)
      .with(Symbol, String)
      .and_yield(node_with_valid_client)

    allow(Chef::Search::Query)
      .to receive(:new)
      .and_return(query_result)
  end

  describe '#hostnames_from_role' do
    it 'returns hostnames from role' do
      expect(client.hostnames_from_role('some-role')).to eq(['herp'])
    end
  end

  describe '#ips_from_role' do
    it 'returns ips from role' do
      expect(client.ips_from_role('some-role')).to eq(['1.1.1.1'])
    end
  end
end
