# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Release, :release_command do
  describe '.perform' do
    it 'includes examples in the --help output' do
      output = described_class.perform(%w[--help])

      expect(output).to include('Available subcommands:')
      expect(output).to include('Examples:')
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* issue')
    end
  end

  describe '#perform' do
    include_context 'release command #perform'

    context 'when using a valid subcommand' do
      it 'executes the subcommand' do
        command = described_class.new(%w[issue 1.2.3])

        expect(command)
          .to receive(:issue)
          .with('1.2.3')

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[invalid])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe 'subcommands' do
    let(:version) { '10.9.0' }

    include_context 'release command #perform'

    describe '#issue' do
      let(:instance) { stubbed_instance(version, subcommand: 'issue') }

      it 'validates the provided version string' do
        expect(instance).to receive(:validate_version!).with(version)

        instance.perform
      end

      it 'runs the trigger' do
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:issue')

        instance.perform
      end
    end

    describe '#merge' do
      let(:instance) { stubbed_instance(version, subcommand: 'merge') }

      it 'validates the provided version string' do
        expect(instance).to receive(:validate_version!).with(version)

        instance.perform
      end

      it 'runs the trigger' do
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:merge')

        instance.perform
      end
    end

    describe '#prepare' do
      let(:instance) { stubbed_instance(version, subcommand: 'prepare') }

      it 'validates the provided version string' do
        expect(instance).to receive(:validate_version!).with(version)

        instance.perform
      end

      it 'runs the trigger' do
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:prepare')

        instance.perform
      end
    end

    describe '#qa' do
      let(:tags) { %w[v1.2.3 v1.3.0-rc1] }
      let(:instance) { stubbed_instance(tags, subcommand: 'qa') }

      it 'validates the provided versions' do
        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original

        instance.perform
      end

      it 'runs the trigger' do
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'release:qa')

        instance.perform
      end
    end

    describe '#tag' do
      let(:instance) { stubbed_instance(version, subcommand: 'tag') }

      it 'validates the provided version string' do
        expect(instance).to receive(:validate_version!).with(version)

        instance.perform
      end

      it 'runs the trigger' do
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:tag')

        instance.perform
      end
    end
  end
end
