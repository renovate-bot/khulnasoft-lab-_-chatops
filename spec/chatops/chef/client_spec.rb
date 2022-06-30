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
    %w[gprd gstg].each do |env|
      it "is true for a disabled #{env} role" do
        allow(Chef::Role)
          .to receive(:load)
          .with("#{env}-cny-omnibus-version")
          .and_return(omnibus_role_enabled)

        expect(client.canary_active_deployment?(env: env)).to eq(false)
      end

      it "is false for an enabled #{env} role" do
        allow(Chef::Role)
          .to receive(:load)
          .with("#{env}-cny-omnibus-version")
          .and_return(omnibus_role_disabled)

        expect(client.canary_active_deployment?(env: env)).to eq(true)
      end

      it "is false for an empty #{env} role" do
        allow(Chef::Role)
          .to receive(:load)
          .with("#{env}-cny-omnibus-version")
          .and_return(omnibus_role_empty)

        expect(client.canary_active_deployment?(env: env)).to eq(false)
      end
    end
  end

  describe '#canary_pipeline_url' do
    %w[gstg gprd].each do |env|
      it "returns the canary pipeline URL for #{env}" do
        allow(Chef::Role)
          .to receive(:load)
          .with("#{env}-cny-omnibus-version")
          .and_return(omnibus_role_enabled)

        expect(client.canary_pipeline_url(env: env)).to eq('https://example.com/some/pipeline/url')
      end
    end
  end

  describe '#environment_unlock' do
    context 'when an environment is unlocked' do
      it 'returns true' do
        expect(Chef::Role)
          .to receive(:load)
          .with('some-env-omnibus-version')
          .and_return(omnibus_role_enabled)

        expect(client.environment_unlocked?('some-env'))
          .to eq(true)
      end
    end

    context 'when an environment is locked' do
      it 'returns false' do
        expect(Chef::Role)
          .to receive(:load)
          .with('some-env-omnibus-version')
          .and_return(omnibus_role_disabled)

        expect(client.environment_unlocked?('some-env'))
          .to eq(false)
      end
    end
  end

  describe '#lock_environment' do
    it 'locks the role for the given environment' do
      expect(Chef::Role)
        .to receive(:load)
        .with('some-env-omnibus-version')
        .and_return(omnibus_role_enabled)

      expect(omnibus_role_enabled).to receive(:save)

      expect { client.lock_environment('some-env') }
        .to change { omnibus_role_enabled.default_attributes.dig('omnibus-gitlab', 'package', 'enable') }
        .from(true).to(false)
    end
  end

  describe '#unlock_environment' do
    it 'unlocks the role for the given environment' do
      expect(Chef::Role)
        .to receive(:load)
        .with('some-env-omnibus-version')
        .and_return(omnibus_role_disabled)

      expect(omnibus_role_disabled).to receive(:save)

      expect { client.unlock_environment('some-env') }
        .to change { omnibus_role_disabled.default_attributes.dig('omnibus-gitlab', 'package', 'enable') }
        .from(false).to(true)
    end
  end
end
