# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::TestsPipeline do
  let(:username) { 'alice' }
  let(:trigger_token) { '456' }
  let(:ops_token) { '123' }
  let(:feature_name) { 'foo' }
  let(:feature_value) { 'bar' }
  let(:chat_user_id) { 'ABCD' }
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

  shared_examples 'end-to-end test does not trigger' do
    it 'does not trigger end-to-end tests' do
      expect(Chatops::Gitlab::Client)
        .not_to receive(:new)

      tests_pipeline.trigger_end_to_end(feature_name, feature_value)
    end
  end

  context 'when environment is production and CHAT_USER_ID is provided' do
    let(:tests_pipeline) do
      described_class.new('gprd')
    end

    let(:project_path) { Chatops::Gitlab::TestsPipeline::PRODUCTION_QUALITY_PROJECT }

    let(:trigger_variables) do
      { feature_toggled: feature_name, feature_value: feature_value, gitlab_username: username, chat_user_id: chat_user_id }
    end

    context 'when TRIGGER_E2E_TESTS is set' do
      around do |example|
        ClimateControl.modify(
          GITLAB_USER_LOGIN: username,
          GITLAB_OPS_TOKEN: ops_token,
          PROD_OPS_E2E_TRIGGER_TOKEN: trigger_token,
          CHAT_USER_ID: chat_user_id,
          TRIGGER_E2E_TESTS: 'true'
        ) { example.run }
      end

      it_behaves_like 'end-to-end test triggers'
    end

    context 'when TRIGGER_E2E_TESTS is not set' do
      around do |example|
        ClimateControl.modify(
          GITLAB_USER_LOGIN: username,
          GITLAB_OPS_TOKEN: ops_token,
          CHAT_USER_ID: chat_user_id,
          PROD_OPS_E2E_TRIGGER_TOKEN: trigger_token
        ) { example.run }
      end

      it_behaves_like 'end-to-end test does not trigger'
    end
  end

  context 'when environment is staging' do
    let(:tests_pipeline) do
      described_class.new('gstg')
    end

    let(:project_path) { Chatops::Gitlab::TestsPipeline::STAGING_QUALITY_PROJECT }

    let(:trigger_variables) do
      { feature_toggled: feature_name, feature_value: feature_value, gitlab_username: username }
    end

    context 'when TRIGGER_E2E_TESTS is set' do
      around do |example|
        ClimateControl.modify(
          GITLAB_USER_LOGIN: username,
          GITLAB_OPS_TOKEN: ops_token,
          STAGING_OPS_E2E_TRIGGER_TOKEN: trigger_token,
          TRIGGER_E2E_TESTS: 'true'
        ) { example.run }
      end

      it_behaves_like 'end-to-end test triggers'
    end

    context 'when TRIGGER_E2E_TESTS is not set' do
      around do |example|
        ClimateControl.modify(
          GITLAB_USER_LOGIN: username,
          GITLAB_OPS_TOKEN: ops_token,
          STAGING_OPS_E2E_TRIGGER_TOKEN: trigger_token
        ) { example.run }
      end

      it_behaves_like 'end-to-end test does not trigger'
    end
  end

  context 'when environment is dev' do
    let(:tests_pipeline) do
      described_class.new('dev')
    end

    it_behaves_like 'end-to-end test does not trigger'
  end
end
