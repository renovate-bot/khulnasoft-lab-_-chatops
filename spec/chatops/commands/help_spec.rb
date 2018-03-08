# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Help do
  let(:command) { described_class.new }

  let(:command1) do
    instance_double('a', command_name: 'a', description: 'Command 1')
  end

  let(:command2) do
    instance_double('b', command_name: 'b', description: 'Command 2')
  end

  before do
    allow(Chatops)
      .to receive(:commands)
      .and_return('a' => command1, 'b' => command2)
  end

  describe '#perform' do
    it 'returns a help message' do
      expect(command.perform).to eq(<<~DESC.strip)
        The following commands are available:

        * `a`: Command 1
        * `b`: Command 2

        For more information about a command you can run it and pass the --help option.
      DESC
    end
  end

  describe '#sorted_command_classes' do
    it 'returns the command classes sorted by name' do
      expect(command.sorted_command_classes).to eq([command1, command2])
    end
  end
end
