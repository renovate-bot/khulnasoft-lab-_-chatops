# frozen_string_literal: true

RSpec.shared_context 'release command #perform' do
  let(:stubbed_client) { double.as_null_object }

  before do
    stub_const('Chatops::Gitlab::Client', stubbed_client)
  end
end

RSpec.shared_examples 'with a valid chatops job' do |input:|
  context 'with a valid chatops job' do
    it 'returns the job URL' do
      instance = stubbed_instance(*input)
      job = instance_double(
        'Objectified Hash',
        id: 123,
        web_url: 'https://gitlab.example.com/job'
      )

      allow(instance).to receive(:pipeline_jobs).and_return([job])

      expect(instance.perform).to end_with('https://gitlab.example.com/job')
    end
  end
end

RSpec.shared_examples 'with an invalid chatops job' do |input:|
  context 'with an invalid chatops job' do
    it 'returns the pipeline URL' do
      instance = stubbed_instance(*input)
      pipeline = instance_double(
        'pipeline',
        id: 123,
        web_url: 'https://gitlab.example.com/pipeline'
      )

      allow(instance).to receive(:run_trigger).and_return(pipeline)
      allow(instance).to receive(:chatops_job?).and_return(false)

      expect(instance.perform).to end_with('https://gitlab.example.com/pipeline')
    end
  end
end

RSpec.shared_examples 'with a dry-run flag' do |input:|
  context 'with a `--dry-run` option' do
    it 'sets the `TEST` trigger variable' do
      instance = stubbed_instance(*input, dry_run: true)

      expect(stubbed_client).to receive(:run_trigger)
        .with(anything, anything, anything, a_hash_including(TEST: 'true'))

      instance.perform
    end
  end
end

RSpec.shared_examples 'with a critical flag' do |input:|
  context 'with `--security` and `--critical` options' do
    it 'sets the `SECURITY` trigger variable' do
      instance = stubbed_instance(*input, security: true, critical: true)

      expect(stubbed_client).to receive(:run_trigger)
        .with(anything, anything, anything,
              a_hash_including(SECURITY: 'critical'))

      instance.perform
    end
  end

  context 'with only a `--critical` option' do
    it 'does not set the `SECURITY` trigger variable' do
      instance = stubbed_instance(*input, critical: true)

      expect(stubbed_client).not_to receive(:run_trigger)
        .with(anything, anything, anything,
              a_hash_including(SECURITY: 'critical'))
      instance.perform
    end
  end
end
