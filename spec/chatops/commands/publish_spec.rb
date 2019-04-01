# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Publish, :release_command do
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

    it 'runs the trigger' do
      expect(stubbed_client)
        .to trigger_release(RELEASE_VERSION: '10.9.0', TASK: 'publish')

      stubbed_instance('10.9.0').perform
    end

    include_examples 'with a valid chatops job',    input: '10.9.0'
    include_examples 'with an invalid chatops job', input: '10.9.0'
  end
end
