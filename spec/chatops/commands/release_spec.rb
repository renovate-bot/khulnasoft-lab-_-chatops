# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Release do
  def stubbed_instance(version)
    env = { 'GITLAB_TOKEN' => 'a', 'RELEASE_TRIGGER_TOKEN' => 'b' }

    described_class.new([version], {}, env).tap do |instance|
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
      stubbed_instance('10.9.0').perform

      expect(stubbed_client).to have_received(:run_trigger)
        .with(
          described_class::TARGET_PROJECT, 'b', described_class::TARGET_REF,
          a_hash_including(RELEASE_VERSION: '10.9.0', TASK: 'release')
        )
    end

    context 'with a valid chatops job' do
      it 'returns the job URL' do
        instance = stubbed_instance('10.9.0')
        job = instance_double('Objectified Hash', id: 123)

        allow(instance).to receive(:pipeline_jobs).and_return([job])

        expect(instance.perform).to end_with(instance.job_url(job))
      end
    end

    context 'with an invalid chatops job' do
      it 'returns the pipeline URL' do
        instance = stubbed_instance('10.9.0')
        pipeline = instance_double('pipeline', id: 123)

        allow(instance).to receive(:run_trigger).and_return(pipeline)
        allow(instance).to receive(:chatops_job?).and_return(false)

        expect(instance.perform).to end_with(instance.pipeline_url(pipeline))
      end
    end
  end
end
