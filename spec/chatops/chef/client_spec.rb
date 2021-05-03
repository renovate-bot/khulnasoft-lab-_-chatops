# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Chef::Client do
  let(:client) do
    ClimateControl.modify(
      CHEF_PEM_KEY: 'fake_key',
      CHEF_USERNAME: 'fake_user'
    ) do
      described_class.new
    end
  end

  let(:query_result) { instance_double('chef search results') }
  let(:node_with_valid_client) do
    { 'hostname' => 'herp', 'ipaddress' => '1.1.1.1' }
  end

  let(:omnibus_role_enabled) do
    instance_double(
      'enabled role result',
      default_attributes: {
        'omnibus-gitlab' => {
          'package' => {
            'version' => 'some-version',
            'enable' => true,
            '__CI_PIPELINE_URL' => 'https://example.com/some/pipeline/url'
          }
        }
      }
    )
  end

  let(:omnibus_role_disabled) do
    instance_double(
      'disabled role result',
      default_attributes: {
        'omnibus-gitlab' => {
          'package' => {
            'version' => 'some-version',
            'enable' => false
          }
        }
      }
    )
  end

  let(:omnibus_role_empty) { instance_double('role result', default_attributes: {}) }

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
      allow(Chef::Role)
        .to receive(:load)
        .with('some-env-omnibus-version')
        .and_return(omnibus_role_enabled)

      expect(client.package_version('some-env')).to eq('some-version')
    end

    it 'returns `unknown` for a Chef role that does not have a package key' do
      allow(Chef::Role)
        .to receive(:load)
        .and_return(omnibus_role_empty)

      expect(client.package_version('some-env')).to eq('unknown')
    end
  end

  describe '#canary_active_deployment?' do
    it 'true for an disabled role' do
      allow(Chef::Role)
        .to receive(:load)
        .with('gprd-cny-omnibus-version')
        .and_return(omnibus_role_enabled)

      expect(client.canary_active_deployment?).to eq(false)
    end

    it 'false for a enabled role' do
      allow(Chef::Role)
        .to receive(:load)
        .with('gprd-cny-omnibus-version')
        .and_return(omnibus_role_disabled)

      expect(client.canary_active_deployment?).to eq(true)
    end

    it 'false for an empty role' do
      allow(Chef::Role)
        .to receive(:load)
        .with('gprd-cny-omnibus-version')
        .and_return(omnibus_role_empty)

      expect(client.canary_active_deployment?).to eq(false)
    end
  end

  describe '#canary_pipeline_url' do
    it 'returns the pipeline URL' do
      allow(Chef::Role)
        .to receive(:load)
        .with('gprd-cny-omnibus-version')
        .and_return(omnibus_role_enabled)

      expect(client.canary_pipeline_url).to eq('https://example.com/some/pipeline/url')
    end
  end
end
