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
      it 'triggers a normal release' do
        instance = stubbed_instance('issue', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:issue')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('issue', version, security: true)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'security:issue')

        instance.perform
      end
    end

    describe '#merge' do
      it 'triggers a normal release' do
        instance = stubbed_instance('merge', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release).with(
          version,
          'release:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => false)
        )

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('merge', nil, security: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release).with(
          nil,
          'security:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => false)
        )

        instance.perform
      end

      it 'triggers a security release with a `--master` flag' do
        instance = stubbed_instance('merge', '--master', nil, security: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release).with(
          nil,
          'security:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => true)
        )

        instance.perform
      end
    end

    describe '#prepare' do
      it 'triggers a normal release' do
        instance = stubbed_instance('prepare', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:prepare')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('prepare', nil, security: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:prepare')

        instance.perform
      end
    end

    describe '#qa' do
      it 'triggers a normal release' do
        tags = %w[v1.2.3 v1.3.0-rc1]
        instance = stubbed_instance('qa', tags)

        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'release:qa')

        instance.perform
      end

      it 'triggers a security release' do
        tags = %w[v1.2.3 v1.3.0-rc1]
        instance = stubbed_instance('qa', tags, security: true)

        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'security:qa')

        instance.perform
      end
    end

    describe '#tag' do
      it 'triggers a normal release' do
        instance = stubbed_instance('tag', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:tag')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('tag', version, security: true)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'security:tag')

        instance.perform
      end
    end
  end
end
