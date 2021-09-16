# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::TestsPipeline do
  let(:username) { 'alice' }
  let(:trigger_token) { '456' }
  let(:ops_token) { '123' }
  let(:feature_name) { 'foo' }
  let(:feature_value) { 'bar' }
  let(:client) { instance_double(Chatops::Gitlab::Client) }
  let(:response) { instance_double('response', web_url: 'some_url') }

  shared_examples 'end-to-end test triggers' do
    it 'triggers end-to-end tests' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: ops_token, host: 'ops.gitlab.net')
        .and_return(client)

      expect(client).to receive(:run_trigger)
        .with(project_path, trigger_token, 'master', trigger_variables)
        .and_return(response)

      tests_pipeline.trigger_end_to_end(feature_name, feature_value)
    end
  end

  context 'when environment is production' do
    around do |example|
      ClimateControl.modify(
        GITLAB_USER_LOGIN: username,
        GITLAB_OPS_TOKEN: ops_token,
        PROD_OPS_E2E_TRIGGER_TOKEN: trigger_token
      ) { example.run }
    end

    let(:tests_pipeline) do
      described_class.new('gprd')
    end

    let(:project_path) { Chatops::Gitlab::TestsPipeline::PRODUCTION_QUALITY_PROJECT }

    let(:trigger_variables) do
      { SMOKE_ONLY: true, feature_toggled: feature_name, feature_value: feature_value, toggled_by: username }
    end

    it_behaves_like 'end-to-end test triggers'
  end

  context 'when environment is staging' do
    around do |example|
      ClimateControl.modify(
        GITLAB_USER_LOGIN: username,
        GITLAB_OPS_TOKEN: ops_token,
        STAGING_OPS_E2E_TRIGGER_TOKEN: trigger_token
      ) { example.run }
    end

    let(:tests_pipeline) do
      described_class.new('gstg')
    end

    let(:project_path) { Chatops::Gitlab::TestsPipeline::STAGING_QUALITY_PROJECT }

    let(:trigger_variables) do
      { feature_toggled: feature_name, feature_value: feature_value, toggled_by: username }
    end

    it_behaves_like 'end-to-end test triggers'
  end

  context 'when environment is dev' do
    let(:tests_pipeline) do
      described_class.new('dev')
    end

    it 'does not trigger end-to-end tests' do
      expect(Chatops::Gitlab::Client)
        .not_to receive(:new)

      tests_pipeline.trigger_end_to_end(feature_name, feature_value)
    end
  end
end
