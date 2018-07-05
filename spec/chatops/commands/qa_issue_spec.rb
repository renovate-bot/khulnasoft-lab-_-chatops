# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::QaIssue do
  def stubbed_instance(version, arguments = {})
    env = {
      'GITLAB_TOKEN' => 'a',
      'GITLAB_USER_LOGIN' => 'j.doe',
      'RELEASE_TRIGGER_TOKEN' => 'b'
    }

    described_class.new([version], arguments, env).tap do |instance|
      # Default to the happy path
      allow(instance).to receive(:chatops_job?).and_return(true)
    end
  end

  describe '#perform' do
    let(:stubbed_client) { double.as_null_object }

    before do
      stub_const('Gitlab::Client', stubbed_client)
    end

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
          .to raise_error(ArgumentError, /Invalid version provided/)
      end
    end

    it 'runs the trigger' do
      stubbed_instance('v11.1.0-rc1..v11.1.0-rc2').perform

      expect(stubbed_client).to have_received(:run_trigger)
        .with(
          described_class::TARGET_PROJECT, 'b', described_class::TARGET_REF,
          a_hash_including(
            RELEASE_USER: 'j.doe',
            RELEASE_VERSION: 'v11.1.0-rc1,v11.1.0-rc2',
            TASK: 'qa_issue'
          )
        )
    end

    context 'with a valid chatops job' do
      it 'returns the job URL' do
        instance = stubbed_instance('v11.1.0-rc1..v11.1.0-rc2')
        job = instance_double('Objectified Hash', id: 123)

        allow(instance).to receive(:pipeline_jobs).and_return([job])

        expect(instance.perform).to end_with(instance.job_url(job))
      end
    end

    context 'with an invalid chatops job' do
      it 'returns the pipeline URL' do
        instance = stubbed_instance('v11.1.0-rc1..v11.1.0-rc2')
        pipeline = instance_double('pipeline', id: 123)

        allow(instance).to receive(:run_trigger).and_return(pipeline)
        allow(instance).to receive(:chatops_job?).and_return(false)

        expect(instance.perform).to end_with(instance.pipeline_url(pipeline))
      end
    end
  end
end
