# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::FeatureDefinition do
  let(:client) { instance_double(Chatops::Gitlab::Client) }
  let(:feature_name) { 'usage_data_api' }
  let(:introduced_by_url) { 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/41301' }
  let(:rollout_issue_project_path) { 'gitlab-org/gitlab' }
  let(:rollout_issue_iid) { '267114' }
  let(:rollout_issue_url) { "https://gitlab.com/#{rollout_issue_project_path}/-/issues/#{rollout_issue_iid}" }
  let(:milestone) { '13.4' }
  let(:type) { 'development' }
  let(:group_label) { 'group::analytics instrumentation' }
  let(:default_enabled) { true }
  let(:definition_yaml) do
    <<~YAML.chomp
      ---
      name: #{feature_name}
      introduced_by_url: #{introduced_by_url}
      rollout_issue_url: #{rollout_issue_url}
      milestone: '#{milestone}'
      type: #{type}
      group: #{group_label}
      default_enabled: #{default_enabled}
    YAML
  end

  def expect_ff_definition_file_api_calls(client:, ff_definition_path:, definition_yaml: nil)
    search_results = ff_definition_path ? [{ 'path' => ff_definition_path }] : []

    expect(client)
      .to receive(:search_in_project)
      .with(
        'gitlab-org/gitlab',
        'blobs',
        "#{feature_name} file:^(config/feature_flags/|ee/config/feature_flags/)"
      )
      .and_return(search_results)

    return unless ff_definition_path

    expect(client)
      .to receive(:file_contents)
      .with(
        project: 'gitlab-org/gitlab',
        path: ff_definition_path
      )
      .and_return(definition_yaml)
  end

  shared_examples 'field fetched from the YAML definition file' do |field|
    subject(:feature_flag_definition) { described_class.new(name: feature_name, env: { 'GITLAB_TOKEN' => '123' }) }

    let(:ff_definition_path) { "config/feature_flags/development/#{feature_name}.yml" }

    it 'returns the correct field from the definition YAML file' do
      expect(feature_flag_definition.environment)
        .to receive(:api_client)
        .and_return(client)

      expect_ff_definition_file_api_calls(client: client, ff_definition_path: ff_definition_path, definition_yaml: definition_yaml)

      expect(feature_flag_definition.public_send(field)).to eq(public_send(field))
    end

    context 'with no search results' do
      it 'returns nil for the field value' do
        expect(feature_flag_definition.environment)
          .to receive(:api_client)
          .and_return(client)

        expect_ff_definition_file_api_calls(client: client, ff_definition_path: nil)

        expect(feature_flag_definition.public_send(field)).to eq(nil)
      end
    end

    context 'with the search for a definition file returns 500' do
      let(:internal_server_error_response) do
        instance_double(
          'response',
          code: 500,
          request: instance_double('request', base_uri: 'foo', path: ''),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
        )
      end

      it 'returns nil for the field value' do
        expect(feature_flag_definition.environment)
          .to receive(:api_client)
          .and_return(client)

        expect(client)
          .to receive(:search_in_project)
          .with(
            'gitlab-org/gitlab',
            'blobs',
            "#{feature_name} file:^(config/feature_flags/|ee/config/feature_flags/)"
          )
          .and_raise(::Gitlab::Error::InternalServerError.new(internal_server_error_response))

        expect(feature_flag_definition.public_send(field)).to eq(nil)
      end
    end

    context 'with a definition file that returns 404' do
      it 'returns nil for the field value' do
        expect(feature_flag_definition.environment)
          .to receive(:api_client)
          .and_return(client)

        expect_ff_definition_file_api_calls(client: client, ff_definition_path: ff_definition_path, definition_yaml: nil)

        expect(feature_flag_definition.public_send(field)).to eq(nil)
      end
    end
  end

  describe '#introduced_by_url' do
    it_behaves_like 'field fetched from the YAML definition file', 'introduced_by_url'
  end

  describe '#rollout_issue_url' do
    it_behaves_like 'field fetched from the YAML definition file', 'rollout_issue_url'
  end

  describe '#milestone' do
    it_behaves_like 'field fetched from the YAML definition file', 'milestone'
  end

  describe '#type' do
    it_behaves_like 'field fetched from the YAML definition file', 'type'
  end

  describe '#group_label' do
    it_behaves_like 'field fetched from the YAML definition file', 'group_label'
  end

  describe '#default_enabled' do
    it_behaves_like 'field fetched from the YAML definition file', 'default_enabled'
  end
end
