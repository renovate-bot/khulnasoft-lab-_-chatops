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

  describe '#package_version' do
    it 'returns the package version for a Chef role' do
      role_result = instance_double(
        'role result',
        default_attributes: {
          'omnibus-gitlab' => {
            'package' => {
              'version' => 'some-version'
            }
          }
        }
      )

      allow(Chef::Role)
        .to receive(:load)
        .with('some-env-omnibus-version')
        .and_return(role_result)

      expect(client.package_version('some-env')).to eq('some-version')
    end

    it 'returns `unknown` for a Chef role that does not have a package key' do
      role_result = instance_double('role result', default_attributes: {})

      allow(Chef::Role)
        .to receive(:load)
        .and_return(role_result)

      expect(client.package_version('some-env')).to eq('unknown')
    end
  end
end
