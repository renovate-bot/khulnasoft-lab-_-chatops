# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Tag do
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

    context 'when tagging a normal release' do
      it 'runs the trigger' do
        stubbed_instance('10.9.0').perform

        expect(stubbed_client).to have_received(:run_trigger)
          .with(
            described_class::TARGET_PROJECT, 'b', described_class::TARGET_REF,
            a_hash_including(
              RELEASE_USER: 'j.doe',
              RELEASE_VERSION: '10.9.0',
              TASK: 'tag'
            )
          )
      end
    end

    context 'when tagging a security release' do
      it 'runs the trigger' do
        stubbed_instance('10.9.0', security: true).perform

        expect(stubbed_client).to have_received(:run_trigger)
          .with(
            described_class::TARGET_PROJECT, 'b', described_class::TARGET_REF,
            a_hash_including(
              RELEASE_USER: 'j.doe',
              RELEASE_VERSION: '10.9.0',
              TASK: 'tag_security'
            )
          )
      end
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
