# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Graph do
  let(:config) do
    {
      'category-1' => {
        'graph-1' => {
          'description' => 'This is graph 1',
          'dashboard' => 'foo',
          'panel' => 1
        },
        'graph-2' => {
          'description' => 'This is graph 2',
          'dashboard' => 'foo',
          'panel' => 2
        }
      },
      'category-2' => {
        'graph-3' => {
          'description' => 'This is graph 3',
          'dashboard' => 'foo',
          'panel' => 3
        }
      }
    }
  end

  describe '.available_graphs' do
    it 'returns a String describing the available graphs per category' do
      expect(described_class)
        .to receive(:configuration)
        .and_return(config)

      expect(described_class.available_graphs_description).to eq(<<~DESC.strip)
        category-1:
          * graph-1: This is graph 1
          * graph-2: This is graph 2

        category-2:
          * graph-3: This is graph 3
      DESC
    end
  end

  describe '.configuration' do
    it 'returns a Hash containing the available categories and graphs' do
      expect(described_class.configuration).to be_an_instance_of(Hash)
    end
  end

  describe '#perform' do
    context 'when the category is not given' do
      it 'raises ArgumentError' do
        expect { described_class.new.perform }.to raise_error(ArgumentError)
      end
    end

    context 'when the graph name is not given' do
      it 'raises ArgumentError' do
        command = described_class.new(%w[category-1])

        expect { command.perform }.to raise_error(ArgumentError)
      end
    end

    context 'when using a valid category and graph' do
      before do
        allow(described_class)
          .to receive(:configuration)
          .and_return(config)
      end

      it 'downloads a graph and uploads it to Slack' do
        command = described_class
          .new(%w[category-1 graph-1])

        graph = instance_double('graph')
        file = instance_double('file')

        expect(command)
          .to receive(:graph)
          .with('foo', 1)
          .and_return(graph)

        expect(graph)
          .to receive(:download)
          .and_return(file)

        expect(graph)
          .to receive(:url)
          .and_return('http://example.com')

        expect(command)
          .to receive(:upload)
          .with('graph-1', file)

        command.perform
      end
    end
  end

  describe '#upload' do
    it 'uploads a file to Slack' do
      command = described_class
        .new([], {}, 'SLACK_TOKEN' => 'foo', 'CHAT_CHANNEL' => 'bar')

      file = instance_double('file')
      uploader = instance_double('uploader')

      expect(Chatops::Slack::FileUpload)
        .to receive(:new)
        .with(
          file: file,
          type: :png,
          channel: 'bar',
          token: 'foo',
          title: 'Grafana graph: foo'
        )
        .and_return(uploader)

      expect(uploader).to receive(:upload)
      expect(file).to receive(:close)

      command.upload('foo', file)
    end
  end

  describe '#graph' do
    it 'returns a Grafana::Graph' do
      command = described_class.new([], {}, 'GRAFANA_TOKEN' => 'foo')
      graph = command.graph('category-1', 1)

      expect(graph).to be_an_instance_of(Chatops::Grafana::Graph)

      expect(graph.url).to include('from=')
      expect(graph.url).to include('to=')
    end
  end

  describe '#required_argument' do
    context 'when the argument is not present' do
      it 'raises ArgumentError' do
        command = described_class.new

        expect { command.required_argument(0, 'foo') }
          .to raise_error(ArgumentError, /You must specify the foo/)
      end
    end

    context 'when the argument is present' do
      it 'returns the value of the argument' do
        command = described_class.new(%w[foo])

        expect(command.required_argument(0, 'foo')).to eq('foo')
      end
    end
  end

  describe '#grafana_token' do
    context 'without the GRAFANA_TOKEN environment variable' do
      it 'raises KeyError' do
        command = described_class.new

        expect { command.grafana_token }.to raise_error(KeyError)
      end
    end

    context 'with the GRAFANA_TOKEN environment variable' do
      it 'returns the value of the variable' do
        command = described_class.new([], {}, 'GRAFANA_TOKEN' => 'foo')

        expect(command.grafana_token).to eq('foo')
      end
    end
  end

  describe '#slack_token' do
    context 'without the SLACK_TOKEN environment variable' do
      it 'raises KeyError' do
        command = described_class.new

        expect { command.slack_token }.to raise_error(KeyError)
      end
    end

    context 'with the SLACK_TOKEN environment variable' do
      it 'returns the value of the variable' do
        command = described_class.new([], {}, 'SLACK_TOKEN' => 'foo')

        expect(command.slack_token).to eq('foo')
      end
    end
  end

  describe '#channel' do
    context 'without the CHAT_CHANNEL environment variable' do
      it 'raises KeyError' do
        command = described_class.new

        expect { command.channel }.to raise_error(KeyError)
      end
    end

    context 'with the CHAT_CHANNEL environment variable' do
      it 'returns the value of the variable' do
        command = described_class.new([], {}, 'CHAT_CHANNEL' => 'foo')

        expect(command.channel).to eq('foo')
      end
    end
  end

  describe '#configuration_for' do
    let(:command) { described_class.new }

    before do
      allow(described_class)
        .to receive(:configuration)
        .and_return(config)
    end

    context 'when using an invalid category name' do
      it 'raises ArgumentError' do
        expect { command.configuration_for('does-not-exists', 'foo') }
          .to raise_error(ArgumentError)
      end
    end

    context 'when using an invalid graph name' do
      it 'raises ArgumentError' do
        expect { command.configuration_for('category-1', 'foo') }
          .to raise_error(ArgumentError)
      end
    end

    context 'when using a valid category and graph name' do
      it 'returns the configuration for the graph' do
        config = command.configuration_for('category-1', 'graph-1')

        expect(config).to be_an_instance_of(Hash)
      end
    end
  end
end
