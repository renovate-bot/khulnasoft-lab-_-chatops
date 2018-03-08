# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Command do
  let(:command) do
    Class.new do
      def self.name
        'DummyCommand'
      end

      include Chatops::Command
    end
  end

  describe '.command_name' do
    it 'returns the name of the command' do
      expect(command.command_name).to eq('dummy_command')
    end
  end

  describe '.description' do
    it 'sets and gets the description of a command' do
      command.description('Hello')

      expect(command.description).to eq('Hello')
    end
  end

  describe '.usage' do
    it 'returns the usage string of the command' do
      command.usage('Hello')

      expect(command.usage).to eq('Hello')
    end

    it 'returns a default usage string if none was specified' do
      expect(command.usage).to eq('dummy_command [OPTIONS]')
    end
  end

  describe '.perform' do
    it 'executes a command' do
      expect { command.perform }.to raise_error(NotImplementedError)
    end

    it 'includes a default help message' do
      expect(command.perform(%w[--help])).to include('Shows this help message')
    end
  end

  describe '#perform' do
    it 'raises NotImplementedError' do
      expect { command.new.perform }.to raise_error(NotImplementedError)
    end
  end
end
