# frozen_string_literal: true

require 'spec_helper'

describe Chatops do
  describe '.commands' do
    it 'returns a Hash' do
      expect(described_class.commands).to be_an_instance_of(Hash)
      expect(described_class.commands).not_to be_empty
    end
  end

  describe '.run' do
    context 'without a command name' do
      it 'raises CommandError' do
        expect { described_class.run }.to raise_error(
          described_class::CommandError,
          /You must define a command to execute/
        )
      end
    end

    context 'without the CHAT_INPUT environment variable' do
      it 'raises CommandError' do
        expect { described_class.run(%w[foo]) }.to raise_error(
          described_class::CommandError,
          /The CHAT_INPUT environment variable/
        )
      end
    end

    context 'with an invalid command name' do
      it 'raises CommandError' do
        expect { described_class.run(%w[rspec], 'CHAT_INPUT' => 'foo') }
          .to raise_error(
            described_class::CommandError,
            'The command "rspec" does not exist'
          )
      end
    end

    context 'with a valid command' do
      it 'executes the command and returns its output' do
        command = instance_double('command')

        expect(described_class.commands)
          .to receive(:[])
          .with('rspec')
          .and_return(command)

        expect(command)
          .to receive(:perform)
          .with(%w[hello world], 'CHAT_INPUT' => 'hello world')

        described_class.run(%w[rspec], 'CHAT_INPUT' => 'hello world')
      end
    end
  end

  describe '.with_trace_section' do
    it 'wraps the block output in a trace section' do
      expect(described_class)
        .to receive(:puts)
        .ordered
        .with(/section_start/)

      expect(described_class)
        .to receive(:puts)
        .ordered
        .with(/section_end/)

      described_class.with_trace_section { 10 }
    end
  end

  describe '.split_input' do
    it 'splits a string into an ARGV array' do
      expect(described_class.split_input('foo bar')).to eq(%w[foo bar])
    end

    it 'supports quoting of words to treat them as a single value' do
      expect(described_class.split_input('"foo bar"')).to eq(['foo bar'])
    end

    it 'corrects smart quotes' do
      expect(described_class.split_input('foo “bar baz”'))
        .to eq(['foo', 'bar baz'])
    end
  end
end
