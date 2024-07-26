# frozen_string_literal: true

require 'spec_helper'
require 'chatops/commands/orchestrator'

describe Chatops::Commands::Orchestrator do
  let(:orchestrator) { described_class.new }
  let(:consul_client) { instance_double(Chatops::Consul::Client) }
  let(:username) { 'test_user' }

  before do
    allow(orchestrator).to receive(:consul_client).and_return(consul_client)
    allow(orchestrator).to receive(:username).and_return(username)
    allow(orchestrator).to receive(:env).and_return({ 'GITLAB_USER_LOGIN' => username })
  end

  describe '.available_subcommands' do
    it 'returns a markdown list of available commands' do
      expect(described_class.available_subcommands).to eq("* disable\n* enable\n* status")
    end
  end

  describe '#perform' do
    context 'with a valid command' do
      it 'calls the appropriate method' do
        expect(orchestrator).to receive(:enable)
        orchestrator.instance_variable_set(:@arguments, ['enable'])
        orchestrator.perform
        result = orchestrator.unsupported_command
        expect(result).to include("The provided subcommand is invalid.")
        expect(result).to include("The following subcommands are available:")
        expect(result).to include("`disable`")
        expect(result).to include("`enable`")
        expect(result).to include("`status`")
      end
    end

    context 'with an invalid command' do
      it 'returns an error message' do
        orchestrator.instance_variable_set(:@arguments, ['invalid'])
        expect(orchestrator.perform).to include("The provided subcommand is invalid.")
      end
    end
  end

  describe '#enable' do
    it 'enables the orchestrator' do
      expect(consul_client).to receive(:put) do |key, json_string|
        expect(key).to eq(described_class::CONSUL_KEY)
        parsed_json = JSON.parse(json_string)
        expect(parsed_json["status"]).to eq("enabled")
        expect(parsed_json["release_manager"]).to eq(username)
        expect(Time.parse(parsed_json["datetime"])).to be_within(1).of(Time.now)
      end
      expect(orchestrator.logger).to receive(:info).with('Orchestrator enabled}')
      expect(orchestrator.enable).to eq("Orchestrator enabled")
    end
  end

  describe '#disable' do
    it 'disables the orchestrator' do
      expect(consul_client).to receive(:put) do |key, json_string|
        expect(key).to eq(described_class::CONSUL_KEY)
        parsed_json = JSON.parse(json_string)
        expect(parsed_json["status"]).to eq("disabled")
        expect(parsed_json["release_manager"]).to eq(username)
        expect(Time.parse(parsed_json["datetime"])).to be_within(1).of(Time.now)
      end
      expect(orchestrator.logger).to receive(:info).with('Orchestrator disabled')
      expect(orchestrator.disable).to eq("Orchestrator disabled")
    end
  end

  describe '#status' do
    context 'when the key exists' do
      it 'returns the current status of the orchestrator' do
        status = { "status" => "enabled" }
        expect(consul_client).to receive(:get).with(described_class::CONSUL_KEY).and_return(JSON.generate(status))
        expect(orchestrator.logger).to receive(:info).with('Orchestrator status is...', status: "enabled")
        expect(orchestrator.status).to eq("Orchestrator status is enabled")
      end
    end

    context 'when the key does not exist' do
      it 'handles the KeyNotFoundError and returns an appropriate message' do
        expect(consul_client).to receive(:get).with(described_class::CONSUL_KEY).and_raise(Chatops::Consul::Client::KeyNotFoundError.new("Key not found"))
        expect(orchestrator.logger).to receive(:error).with("Failed to retrieve orchestrator status: Key not found")
        expect(orchestrator.status).to eq("Failed to retrieve orchestrator status: Key not found")
      end
    end
  end
end
