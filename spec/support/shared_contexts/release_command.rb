# frozen_string_literal: true

# rubocop:disable RSpec/ContextWording
RSpec.shared_context 'release command #perform' do
  let(:stubbed_client) { double.as_null_object }

  before do
    stub_const('Gitlab::Client', stubbed_client)
  end
end

RSpec.shared_examples 'with a valid chatops job' do |version:|
  context 'with a valid chatops job' do
    it 'returns the job URL' do
      instance = stubbed_instance(version)
      job = instance_double('Objectified Hash', id: 123)

      allow(instance).to receive(:pipeline_jobs).and_return([job])

      expect(instance.perform).to end_with(instance.job_url(job))
    end
  end
end

RSpec.shared_examples 'with an invalid chatops job' do |version:|
  context 'with an invalid chatops job' do
    it 'returns the pipeline URL' do
      instance = stubbed_instance(version)
      pipeline = instance_double('pipeline', id: 123)

      allow(instance).to receive(:run_trigger).and_return(pipeline)
      allow(instance).to receive(:chatops_job?).and_return(false)

      expect(instance.perform).to end_with(instance.pipeline_url(pipeline))
    end
  end
end
# rubocop:enable RSpec/ContextWording
