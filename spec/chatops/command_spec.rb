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

  describe '#gitlab_token' do
    context 'when the GITLAB_TOKEN environment variable is not specified' do
      it 'raises KeyError' do
        expect { command.new.gitlab_token }.to raise_error(KeyError)
      end
    end

    context 'when the GITLAB_TOKEN environment variable is specified' do
      it 'returns the value of the environment variable' do
        cmd = command.new([], {}, 'GITLAB_TOKEN' => '123')

        expect(cmd.gitlab_token).to eq('123')
      end
    end
  end

  describe '#slack_token' do
    context 'when the SLACK_TOKEN environment variable is not specified' do
      it 'raises KeyError' do
        expect { command.new.slack_token }.to raise_error(KeyError)
      end
    end

    context 'when the SLACK_TOKEN environment variable is specified' do
      it 'returns the value of the environment variable' do
        cmd = command.new([], {}, 'SLACK_TOKEN' => '123')

        expect(cmd.slack_token).to eq('123')
      end
    end
  end

  describe '#channel' do
    context 'when the CHAT_CHANNEL environment variable is not specified' do
      it 'raises KeyError' do
        expect { command.new.channel }.to raise_error(KeyError)
      end
    end

    context 'when the CHAT_CHANNEL environment variable is specified' do
      it 'returns the value of the environment variable' do
        cmd = command.new([], {}, 'CHAT_CHANNEL' => '123')

        expect(cmd.channel).to eq('123')
      end
    end
  end

  describe '#grafana_token' do
    context 'when the GRAFANA_TOKEN environment variable is not specified' do
      it 'raises KeyError' do
        expect { command.new.grafana_token }.to raise_error(KeyError)
      end
    end

    context 'when the GRAFANA_TOKEN environment variable is specified' do
      it 'returns the value of the environment variable' do
        cmd = command.new([], {}, 'GRAFANA_TOKEN' => '123')

        expect(cmd.grafana_token).to eq('123')
      end
    end
  end
end
