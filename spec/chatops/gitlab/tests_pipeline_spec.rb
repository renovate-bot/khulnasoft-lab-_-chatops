# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::TestsPipeline do
  let(:feature_name) { 'foo' }
  let(:feature_value) { 'true' }
  let(:environment) { 'gprd' }
  let(:options) do
    { project: nil, group: nil, user: nil }
  end
  let(:tests_pipeline) do
    described_class.new(environment, options, feature_name, feature_value)
  end

  shared_examples 'end-to-end test triggers' do
    let(:username) { 'alice' }
    let(:chat_user_id) { 'ABCD' }
    let(:trigger_token) { '456' }
    let(:ops_token) { '123' }
    let(:client) { instance_double(Chatops::Gitlab::Client) }
    let(:project_path) { Chatops::Gitlab::TestsPipeline::PRODUCTION_QUALITY_PROJECT }
    let(:response) { instance_double('response', web_url: 'some_url') }
    let(:trigger_variables) do
      { feature_toggled: feature_name, feature_value: feature_value, gitlab_username: username, chat_user_id: chat_user_id, SMOKE_ONLY: 'true' }
    end

    around do |example|
      ClimateControl.modify(
        GITLAB_USER_LOGIN: username,
        GITLAB_OPS_TOKEN: ops_token,
        PROD_OPS_E2E_TRIGGER_TOKEN: trigger_token,
        CHAT_USER_ID: chat_user_id,
        TRIGGER_E2E_TESTS: 'true'
      ) { example.run }
    end

    it 'triggers end-to-end tests' do
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: ops_token, host: 'ops.gitlab.net')
        .and_return(client)

      expect(client).to receive(:run_trigger)
        .with(project_path, trigger_token, 'master', trigger_variables)
        .and_return(response)

      tests_pipeline.trigger_end_to_end
    end
  end

  shared_examples 'end-to-end test does not trigger' do
    it 'does not trigger end-to-end tests' do
      expect(Chatops::Gitlab::Client)
        .not_to receive(:new)

      tests_pipeline.trigger_end_to_end
    end
  end

  context 'when should_triggers? returns true' do
    before do
      allow(tests_pipeline)
        .to receive(:should_triggers?)
        .and_return(true)
    end

    it_behaves_like 'end-to-end test triggers'
  end

  context 'when should_triggers? returns false' do
    before do
      allow(tests_pipeline)
        .to receive(:should_triggers?)
        .and_return(false)
    end

    it_behaves_like 'end-to-end test does not trigger'
  end

  describe '#should_trigger? when TRIGGER_E2E_TESTS is set' do
    around do |example|
      ClimateControl.modify(
        TRIGGER_E2E_TESTS: 'true'
      ) { example.run }
    end

    let(:options) do
      { project: nil, group: nil, user: nil }
    end

    context 'when env is gprd and group, project and user are not specified' do
      it { expect(tests_pipeline.should_trigger?).to eq true }
    end

    context 'when feature_value is false' do
      let(:feature_value) { 'false' }

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end

    context 'when feature_value is 90' do
      let(:feature_value) { '90' }

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end

    context 'when feature_value is 100' do
      let(:feature_value) { '100' }

      it { expect(tests_pipeline.should_trigger?).to eq true }
    end

    context 'when a project is specified' do
      let(:options) do
        { project: 'some-project', group: nil, user: nil }
      end

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end

    context 'when a disallowed group is specified' do
      let(:options) do
        { project: nil, group: 'disallowed-group', user: nil }
      end

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end

    context 'when an allowed group is specified' do
      let(:options) do
        { project: nil, group: 'gitlab-qa-sandbox-group', user: nil }
      end

      it { expect(tests_pipeline.should_trigger?).to eq true }
    end

    context 'when a disallowed user is specified' do
      let(:options) do
        { project: nil, group: nil, user: 'disallowed-user' }
      end

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end

    context 'when an allowed user is specified' do
      let(:options) do
        { project: nil, group: nil, user: 'gitlab-qa' }
      end

      it { expect(tests_pipeline.should_trigger?).to eq true }
    end

    context 'when env is dev' do
      let(:environment) { 'dev' }

      it { expect(tests_pipeline.should_trigger?).to eq false }
    end
  end

  describe '#should_trigger? when TRIGGER_E2E_TESTS is not set' do
    let(:environment) { 'gprd' }
    let(:tests_pipeline) { described_class.new(environment, options, feature_name, feature_value) }

    let(:options) do
      { project: nil, group: nil, user: nil }
    end

    around do |example|
      ClimateControl.modify(
        TRIGGER_E2E_TESTS: nil
      ) { example.run }
    end

    it { expect(tests_pipeline.should_trigger?).to eq false }
  end
end
