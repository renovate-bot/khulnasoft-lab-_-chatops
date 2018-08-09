# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::QaIssue, :release_command do
  describe '#perform' do
    include_context 'release command #perform'

    it 'raises an error when no argument is given' do
      expect { described_class.new.perform }
        .to raise_error(ArgumentError, 'You must specify the comparison!')
    end

    it 'validates the provided comparison string', :aggregate_failures do
      valid = %w[
        v11.1.0-rc1..v11.1.0-rc2
        v11.1.0..v11.1.1
      ]
      invalid = %w[
        11.1.0-rc1..11.1.0-rc2
        v11.1..v11.1.0-rc2
      ]

      valid.each do |comparison|
        expect { stubbed_instance(comparison).perform }.not_to raise_error
      end

      invalid.each do |comparison|
        expect { stubbed_instance(comparison).perform }
          .to raise_error(ArgumentError, /Invalid tag provided/)
      end

      expect { stubbed_instance('v11.1.0-rc1').perform }
        .to raise_error(ArgumentError, /Invalid comparison provided/)
    end

    it 'supports a --security option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[v1.2.3], { security: true }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[v1.2.3 --security])
    end

    context 'when creating a normal issue' do
      it 'runs the trigger' do
        expect(stubbed_client).to trigger_release(
          RELEASE_VERSION: 'v11.1.0-rc1,v11.1.0-rc2',
          TASK: 'qa_issue'
        )

        stubbed_instance('v11.1.0-rc1..v11.1.0-rc2').perform
      end
    end

    context 'when creating a security issue' do
      it 'runs the trigger' do
        expect(stubbed_client).to trigger_release(
          RELEASE_VERSION: 'v11.1.0-rc1,v11.1.0-rc2',
          TASK: 'security_qa_issue'
        )

        stubbed_instance('v11.1.0-rc1..v11.1.0-rc2', security: true).perform
      end
    end

    version = 'v11.1.0-rc1..v11.1.0-rc2'

    include_examples 'with a valid chatops job', version: version
    include_examples 'with an invalid chatops job', version: version
  end
end
