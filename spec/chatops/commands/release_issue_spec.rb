# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::ReleaseIssue, :release_command do
  describe '#perform' do
    include_context 'release command #perform'

    it 'raises an error when no argument is given' do
      expect { described_class.new.perform }
        .to raise_error(ArgumentError, 'You must specify the version!')
    end

    it 'validates the provided version string', :aggregate_failures do
      valid   = %w[10.9.0 10.9.1 10.9.0-rc1]
      invalid = %w[10.9.0-ee 10.9.0-rc1-ee 10.9 10.9.0-rc]

      valid.each do |version|
        expect { stubbed_instance(version).perform }
          .not_to raise_error
      end

      invalid.each do |version|
        expect { stubbed_instance(version).perform }
          .to raise_error(ArgumentError, "Invalid version provided: #{version}")
      end
    end

    it 'supports a --security option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[1.2.3], { security: true }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[1.2.3 --security])
    end

    context 'with a security release' do
      it 'runs the trigger' do
        expect(stubbed_client).to trigger_release(
          RELEASE_VERSION: '10.9.0',
          TASK: 'security_patch_issue'
        )

        stubbed_instance('10.9.0', security: true).perform
      end
    end

    context 'with a monthly release' do
      it 'runs the trigger' do
        expect(stubbed_client).to trigger_release(
          RELEASE_VERSION: '10.9.0',
          TASK: 'monthly_issue'
        )

        stubbed_instance('10.9.0').perform
      end
    end

    context 'with a patch release' do
      it 'runs the trigger' do
        expect(stubbed_client).to trigger_release(
          RELEASE_VERSION: '10.9.0-rc5',
          TASK: 'patch_issue'
        )

        stubbed_instance('10.9.0-rc5').perform
      end
    end

    include_examples 'with a valid chatops job',    version: '10.9.0'
    include_examples 'with an invalid chatops job', version: '10.9.0'
  end
end
