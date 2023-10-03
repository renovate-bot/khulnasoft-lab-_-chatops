# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Feature do
  using RSpec::Parameterized::TableSyntax

  shared_examples 'invalid feature flag update' do
    let(:error_message) { /Unable to proceed due to inconsistent feature flag status. When the flag on production is turned on, staging should be on too./ }
    let(:command_args) { %w[set foo] + [value] }
    let(:staging) { false }
    let(:command_opts_this_env) { staging ? command_opts.merge(staging: true) : command_opts }
    let(:command_opts_other_env) { staging ? command_opts : command_opts.merge(staging: true) }
    let(:feature_enabled) { false }
    let(:feature) do
      instance_double(
        'feature',
        name: 'foo',
        state: 'conditional',
        gates: gates,
        enabled?: feature_enabled
      )
    end

    it 'does not set the feature flag' do
      command_envs = {
        'CHAT_CHANNEL' => '456',
        'GITLAB_TOKEN' => '123',
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_STAGING_REF_TOKEN' => '654',
        'GITLAB_USER_LOGIN' => 'alice'
      }
      command = described_class.new(command_args, command_opts_this_env, command_envs)

      # needed to initialize environments
      _ = command.environments

      other_env_feature_command = instance_double('Chatops::Commands::Feature')

      expect(described_class)
        .to receive(:new)
        .with(%w[get foo], command_opts_other_env, command_envs)
        .and_return(other_env_feature_command)

      expect(command)
        .to receive(:production_check?)
        .and_return(true)

      allow(command)
        .to receive(:production_channel_id)
        .and_return(command.env['CHAT_CHANNEL'])

      expect(other_env_feature_command)
        .to receive(:get_feature).with('foo', Chatops::GitlabEnvironments::Environment.staging)
        .and_return(feature)

      expect(command.set).to match(error_message)
    end
  end

  # rubocop: disable RSpec/ExampleLength
  # rubocop: disable RSpec/MultipleExpectations
  shared_examples 'valid feature flag update' do
    let(:feature_enabled) { true }
    let(:host) { 'gitlab.com' }
    let(:token) { '123' }
    let(:tag_env) { ['gprd'] }

    it 'sets the feature flag' do
      command_envs = {
        'CHAT_CHANNEL' => 'chan',
        'GITLAB_TOKEN' => '123',
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_STAGING_REF_TOKEN' => '654',
        'GITLAB_USER_LOGIN' => 'alice'
      }
      command = described_class.new(command_args, command_opts, command_envs)

      environment = command.environments.first
      client = instance_double('Chatops::Gitlab::Client')
      staging_feature_command = instance_double('Chatops::Commands::Feature')
      feature = instance_double(
        'feature',
        name: 'foo',
        state: 'conditional',
        gates: gates
      )

      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: token, host: host)
        .and_return(client)

      allow(described_class)
        .to receive(:new)
        .with(%w[get foo], command_opts.merge(staging: true), command_envs)
        .and_return(staging_feature_command)

      expect(client)
        .to receive(:set_feature)
        .with(*set_feature_params)
        .and_return(feature)

      allow(staging_feature_command)
        .to receive(:get_feature).with('foo', Chatops::GitlabEnvironments::Environment.staging)
        .and_return(feature)

      allow(feature)
        .to receive(:enabled?)
        .and_return(feature_enabled)

      allow(command)
        .to receive(:production_channel_id)
        .and_return(command.env['CHAT_CHANNEL'])

      expect(command)
        .to receive(:production_check?)
        .and_return(true)

      issue = instance_double('GitLab::Issue')

      expect(command)
        .to receive(:log_feature_toggle)
        .with(log_feature_toggle_fields[:feature_name], log_feature_toggle_fields[:feature_value], environment)
        .and_return(issue)

      events_client = instance_double('Chatops::Events::Client')

      expect(Chatops::Events::Client)
        .to receive(:new)
        .with(any_args)
        .and_return(events_client)

      expect(events_client)
        .to receive(:send_event)
        .with(
          "Feature flag '#{log_feature_toggle_fields[:feature_name]}' " \
          "has been set to '#{log_feature_toggle_fields[:feature_value]}' " \
          "on #{environment.env_name}",
          fields: log_feature_toggle_fields
        )

      tests_pipeline = instance_double('Chatops::Gitlab::TestsPipeline')

      expect(Chatops::Gitlab::TestsPipeline)
        .to receive(:new)
        .with(any_args)
        .and_return(tests_pipeline)

      expect(tests_pipeline)
        .to receive(:trigger_end_to_end)
        .and_return(:ops_pipeline)

      annotate = instance_double('annotate')

      expect(Chatops::Grafana::Annotate)
        .to receive(:new)
        .with(token: 'some-grafana-token')
        .and_return(annotate)

      expect(annotate)
        .to receive(:annotate!)
        .with(
          "alice set feature flag #{log_feature_toggle_fields[:feature_name]} to #{log_feature_toggle_fields[:feature_value]}",
          tags: tag_env + ['feature-flag', log_feature_toggle_fields[:feature_name]]
        )

      expect(command)
        .to receive(:send_feature_details)
        .with(
          feature: an_instance_of(Chatops::Gitlab::Feature),
          text: 'The feature flag value has been updated!',
          environment: environment
        )

      expect(command)
        .to receive(:send_feature_toggling_to_qa_channel)
        .with(issue, environment, :ops_pipeline)

      command.set
    end
  end
  # rubocop: enable RSpec/ExampleLength
  # rubocop: enable RSpec/MultipleExpectations

  shared_context 'with feature name tables with backticks' do
    where(:feature_name, :expected_feature_name) do
      '`foo`' | 'foo'
      '`foo'  | '`foo'
      'foo`'  | 'foo`'
      'f`oo`' | 'f`oo`'
      'foo'   | 'foo'
      '`drop_sidekiq_jobs_ComplianceManagement::Standards::Gitlab::AtLeastTwoApprovalsWorker`' | 'drop_sidekiq_jobs_ComplianceManagement::Standards::Gitlab::AtLeastTwoApprovalsWorker'
    end
  end

  describe '.perform' do
    it 'supports a --match option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(match: 'gitaly'),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --match gitaly])
    end

    it 'supports a --staging option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: true, staging_ref: false, dev: false, ops: false, pre: false),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --staging])
    end

    it 'supports a --staging-ref option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: false, staging_ref: true, dev: false, ops: false, pre: false),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --staging-ref])
    end

    it 'supports a --dev option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: false, staging_ref: false, dev: true, ops: false, pre: false),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --dev])
    end

    it 'supports a --ops option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: false, staging_ref: false, dev: false, ops: true, pre: false),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --ops])
    end

    it 'supports a --pre option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: false, staging_ref: false, dev: false, ops: false, pre: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --pre])
    end

    it 'supports a --ignore-production-check option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature set foo true],
          a_hash_including(ignore_production_check: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature set foo true --ignore-production-check])
    end

    it 'supports a --ignore-feature-flag-consistency-check option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature set foo true],
          a_hash_including(ignore_feature_flag_consistency_check: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature set foo true --ignore-feature-flag-consistency-check])
    end
  end

  describe '.available_subcommands' do
    it 'returns a Markdown list' do
      expect(described_class.available_subcommands).to eq(<<~LIST.strip)
        * delete
        * get
        * list
        * set
      LIST
    end
  end

  describe '#perform' do
    context 'when using a valid command' do
      it 'executes the command' do
        command = described_class.new(%w[get])

        expect(command).to receive(:get)

        command.perform
      end
    end

    context 'when using an invalid command' do
      it 'returns an error message' do
        command = described_class.new(%w[kittens])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '#unsupported_command' do
    it 'produces a message explaining the command is invalid' do
      command = described_class.new

      expect(command.unsupported_command)
        .to match(/The feature subcommand is invalid/)
    end
  end

  describe '#get' do
    context 'when not specifying a feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[get])

        expect(command.get).to match(/You must specify the name of the feature/)
      end
    end

    context 'when using a non-existing feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321', 'GITLAB_STAGING_REF_TOKEN' => '654')
        collection = instance_double('collection')

        expect(Chatops::Gitlab::FeatureCollection)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(collection)

        expect(collection)
          .to receive(:find_by_name)
          .with('foo')
          .and_return(nil)

        expect(command.get).to match('The feature "foo" does not exist.')
      end
    end

    context 'when using a valid feature name' do
      shared_examples 'sends the details of the feature to Slack' do
        it 'receives the feature details' do
          command = described_class.new(['get', feature_name], {}, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321', 'GITLAB_STAGING_REF_TOKEN' => '654')
          collection = instance_double('collection')
          feature = instance_double('feature')
          environment = command.environments.first

          expect(Chatops::Gitlab::FeatureCollection)
            .to receive(:new)
            .with(token: '123', host: 'gitlab.com')
            .and_return(collection)

          expect(collection)
            .to receive(:find_by_name)
            .with(expected_feature_name)
            .and_return(feature)

          expect(command)
            .to receive(:send_feature_details)
            .with(feature: feature, environment: environment)

          command.get
        end
      end

      include_context 'with feature name tables with backticks'
      with_them do
        it_behaves_like 'sends the details of the feature to Slack'
      end
    end
  end

  describe '#set' do
    let(:default_opts) { { actors: false, random: false, project: nil, group: nil, namespace: nil, user: nil } }

    context 'when not specifying a feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[set], default_opts)

        expect(command.set).to match(/You must specify the name of the feature flag and its new value/)
      end
    end

    context 'when not specifying a feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo], default_opts)

        expect(command.set).to match(/You must specify the name of the feature flag and its new value/)
      end
    end

    context 'when specifying an invalid feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo bar], default_opts)

        expect(command.set).to match(/The value "bar" is invalid/)
      end
    end

    # rubocop: disable RSpec/NestedGroups
    context 'when not specifying --random or --actors for a percentage value' do
      context 'with a value of 0' do
        include_examples 'valid feature flag update' do
          let(:command_args) { %w[set foo 0] }
          let(:command_opts) { default_opts }
          let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 0 }] }
          let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: '0', feature_scope_actors: 'false' } }
          let(:set_feature_params) do
            [
              'foo',
              '0',
              {
                project: nil,
                group: nil,
                feature_group: nil,
                namespace: nil,
                user: nil,
                repository: nil,
                actors: false
              }
            ]
          end
        end
      end

      context 'with a value of 100' do
        include_examples 'valid feature flag update' do
          let(:command_args) { %w[set foo 100] }
          let(:command_opts) { default_opts }
          let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 100 }] }
          let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: '100', feature_scope_actors: 'false' } }
          let(:set_feature_params) do
            [
              'foo',
              '100',
              {
                project: nil,
                group: nil,
                feature_group: nil,
                namespace: nil,
                user: nil,
                repository: nil,
                actors: false
              }
            ]
          end
        end
      end

      context 'with a value of 1' do
        it 'returns an error message' do
          command = described_class.new(%w[set foo 1], default_opts)

          expect(command.set).to match(/One of `--actors` or `--random` must be set for percentage values/)
        end
      end

      context 'with a value of 42' do
        it 'returns an error message' do
          command = described_class.new(%w[set foo 42], default_opts)

          expect(command.set).to match(/One of `--actors` or `--random` must be set for percentage values/)
        end
      end

      context 'with a value of 99' do
        it 'returns an error message' do
          command = described_class.new(%w[set foo 99], default_opts)

          expect(command.set).to match(/One of `--actors` or `--random` must be set for percentage values/)
        end
      end

      context 'when not ignoring the deprecation check' do
        it 'returns an error message' do
          opts = default_opts.merge(random: true)
          command = described_class.new(%w[set foo 99], opts)

          expect(command.set).to match(/Time percentage feature flags are being deprecated in favor of using actors/)
        end
      end
    end
    # rubocop: enable RSpec/NestedGroups

    context 'when using a project feature gate together with --random' do
      it 'returns an error message' do
        opts = default_opts.merge(random: true, project: 'gitlab-org/gitaly')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a project feature gate together with --actors' do
      it 'returns an error message' do
        opts = default_opts.merge(actors: true, project: 'gitlab-org/gitaly')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a group feature gate together with --random' do
      it 'returns an error message' do
        opts = default_opts.merge(random: true, group: 'gitlab-org')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a group feature gate together with --actors' do
      it 'returns an error message' do
        opts = default_opts.merge(actors: true, group: 'gitlab-org')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a group namespace feature gate together with --random' do
      it 'returns an error message' do
        opts = default_opts.merge(random: true, namespace: 'gitlab-org')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a group namespace feature gate together with --actors' do
      it 'returns an error message' do
        opts = default_opts.merge(actors: true, namespace: 'gitlab-org')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a user namespace feature gate together with --random' do
      it 'returns an error message' do
        opts = default_opts.merge(random: true, namespace: 'myuser')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a user namespace feature gate together with --actors' do
      it 'returns an error message' do
        opts = default_opts.merge(actors: true, namespace: 'myuser')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a user feature gate together with --random' do
      it 'returns an error message' do
        opts = default_opts.merge(random: true, user: 'myuser')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using a user feature gate together with --actors' do
      it 'returns an error message' do
        opts = default_opts.merge(actors: true, user: 'myuser')
        command = described_class.new(%w[set foo true], **opts)

        expect(command.set).to match(/`--actors` and `--random` cannot be set together with `--project`, `--group`, `--feature-group`, `--namespace`, `--user`, or `--repository`/)
      end
    end

    context 'when using valid arguments' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo 10] }
        let(:command_opts) { default_opts.merge(random: true, ignore_random_deprecation_check: true) }
        let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 10 }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: '10', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            '10',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: nil,
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end

      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo 0.001] }
        let(:command_opts) { default_opts.merge(random: true, ignore_random_deprecation_check: true) }
        let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 0.001 }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: '0.001', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            '0.001',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: nil,
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a project feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(project: 'gitlab-org/gitaly') }
        let(:gates) { [{ 'project' => 'gitlab-org/gitaly', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_project: 'gitlab-org/gitaly', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: 'gitlab-org/gitaly',
              group: nil,
              feature_group: nil,
              namespace: nil,
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a group feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(group: 'gitlab-org') }
        let(:gates) { [{ 'group' => 'gitlab-org', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_group: 'gitlab-org', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: 'gitlab-org',
              feature_group: nil,
              namespace: nil,
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a group namespace feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(namespace: 'gitlab-org') }
        let(:gates) { [{ 'namespace' => 'gitlab-org', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_namespace: 'gitlab-org', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: 'gitlab-org',
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a user namespace feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(namespace: 'myuser') }
        let(:gates) { [{ 'namespace' => 'myuser', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_namespace: 'myuser', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: 'myuser',
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a user feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(user: 'myuser') }
        let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_user: 'myuser', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: nil,
              user: 'myuser',
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a repository feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { default_opts.merge(repository: 'gitlab-org/gitlab.wiki.git') }
        let(:gates) { [{ 'group' => 'gitlab-org', 'value' => true }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_repository: 'gitlab-org/gitlab.wiki.git', feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              feature_group: nil,
              namespace: nil,
              user: nil,
              repository: 'gitlab-org/gitlab.wiki.git',
              actors: false
            }
          ]
        end
      end
    end

    context 'when using a feature group feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:feature_group) { 'gitlab_team_members' }
        let(:command_opts) { default_opts.merge(feature_group: feature_group) }
        let(:gates) { [{ 'key' => 'groups', 'value' => [feature_group] }] }
        let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_feature_group: feature_group, feature_scope_actors: 'false' } }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              feature_group: feature_group,
              namespace: nil,
              user: nil,
              repository: nil,
              actors: false
            }
          ]
        end
      end
    end

    # rubocop: disable RSpec/NestedGroups
    context 'when the flag is turned off in staging' do
      context 'when turning on production' do
        context 'when setting a boolean value' do
          let(:value) { 'true' }
          let(:command_opts) { default_opts.merge(user: 'myuser') }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update'
        end

        context 'when setting a percentage value' do
          let(:value) { '10' }
          let(:command_opts) { default_opts.merge(random: true, ignore_random_deprecation_check: true) }
          let(:gates) { [{ 'value' => 10, 'key' => 'percentage_of_time' }] }

          include_examples 'invalid feature flag update'
        end

        context 'when the ignore_feature_flag_consistency_check is true' do
          let(:command_args) { %w[set foo true] }
          let(:command_opts) { default_opts.merge(user: 'myuser', ignore_feature_flag_consistency_check: true) }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
          let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_user: 'myuser', feature_scope_actors: 'false' } }
          let(:set_feature_params) do
            [
              'foo',
              'true',
              {
                project: nil,
                group: nil,
                feature_group: nil,
                namespace: nil,
                user: 'myuser',
                repository: nil,
                actors: false
              }
            ]
          end

          include_examples 'valid feature flag update'
        end
      end
    end

    context 'when the feature flag does not exist in staging' do
      context 'when turning on production' do
        context 'when setting a boolean value' do
          let(:value) { 'true' }
          let(:command_opts) { default_opts.merge(user: 'myuser') }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update' do
            let(:feature) { nil }
          end
        end
      end
    end

    context 'when the flag is turned on in production' do
      context 'when turning off in staging' do
        let(:staging) { false }

        context 'when setting a boolean value' do
          let(:value) { 'true' }
          let(:command_opts) { default_opts.merge(user: 'myuser') }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update'
        end

        context 'when setting a percentage value' do
          let(:value) { '10' }
          let(:command_opts) { default_opts.merge(random: true, ignore_random_deprecation_check: true) }
          let(:gates) { [{ 'value' => 10, 'key' => 'percentage_of_time' }] }

          include_examples 'invalid feature flag update'
        end

        context 'when the ignore_feature_flag_consistency_check is true' do
          let(:command_args) { %w[set foo true] }
          let(:command_opts) { default_opts.merge(user: 'myuser', ignore_feature_flag_consistency_check: true, staging: true) }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
          let(:log_feature_toggle_fields) { { feature_name: 'foo', feature_value: 'true', feature_scope_user: 'myuser', feature_scope_actors: 'false' } }
          let(:set_feature_params) do
            [
              'foo',
              'true',
              {
                project: nil,
                group: nil,
                feature_group: nil,
                namespace: nil,
                user: 'myuser',
                repository: nil,
                actors: false
              }
            ]
          end

          include_examples 'valid feature flag update' do
            let(:host) { 'staging.gitlab.com' }
            let(:token) { '321' }
            let(:tag_env) { ['gstg'] }
          end
        end
      end
    end

    context 'with multiple environments' do
      let(:log_feature_toggle_params) { %w[foo deleted] }
      let(:issue) { instance_double('GitLab::Issue') }
      let(:client) { instance_double('client') }
      let(:message) { instance_double('message') }

      let(:command) do
        described_class.new(
          %w[delete foo],
          { dev: true, staging: true, production: true },
          'GITLAB_TOKEN' => '123',
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654',
          'SLACK_TOKEN' => '456',
          'CHAT_CHANNEL' => 'foo'
        )
      end

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(client)
        allow(client).to receive(:delete_feature)
        allow(Chatops::Slack::Message).to receive(:new).and_return(message)
        allow(message).to receive(:send)
        allow(command).to receive(:log_feature_toggle)
        allow(command).to receive(:send_feature_toggle_event)
        allow(command).to receive(:production_channel_id).and_return(command.env['CHAT_CHANNEL'])
      end

      it 'executes the same command to each environment' do
        expect(client).to receive(:delete_feature).exactly(3).times
        expect(command).to receive(:send_feature_toggle_event).with('foo', 'deleted', anything).exactly(3).times
        expect(message).to receive(:send).exactly(3).times
        expect(command).to receive(:log_feature_toggle).with(*log_feature_toggle_params, anything).and_return(issue).exactly(3).times

        command.delete
      end
    end

    context 'when the feature flag does not exist in production' do
      let(:command_opts) { default_opts.merge(user: 'myuser', staging: true) }

      context 'when turning on staging' do
        context 'when setting a boolean value' do
          let(:value) { 'true' }
          let(:command_opts) { default_opts.merge(user: 'myuser') }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update' do
            let(:feature) { nil }
          end
        end
      end
    end
    # rubocop: enable RSpec/NestedGroups

    context 'when there is an ongoing incident' do
      it 'does not allow changing the feature flag state' do
        opts = default_opts.merge(random: true, ignore_random_deprecation_check: true)
        command =
          described_class.new(%w[set foo 10], opts, 'CHAT_CHANNEL' => '456', 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321', 'GITLAB_STAGING_REF_TOKEN' => '654')
        allow(command).to receive(:production_channel_id).and_return(command.env['CHAT_CHANNEL'])

        expect(command).to receive(:production_check?).and_return(false)

        expect(command.set).to match(/production check failure/)
      end
    end

    context 'when the target environment is production' do
      let(:options) { { production: true } }
      let(:env_vars) do
        {
          'CHAT_CHANNEL' => slack_channel,
          'GITLAB_TOKEN' => '123',
          'GITLAB_USER_LOGIN' => 'alice',
          'GRAFANA_TOKEN' => 'some-grafana-token',
          'SLACK_TOKEN' => '456'
        }
      end
      let(:client) { instance_double('client') }
      let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
      let(:feature) { instance_double('feature', name: 'foo', state: 'conditional', gates: gates) }

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(client)
        allow(client).to receive(:set_feature).and_return(feature)
        allow(described_class).to receive(:valid_value?).and_return(true)
      end

      # rubocop: disable RSpec/NestedGroups
      context 'when the channel is production' do
        let(:slack_channel) { 'production' }

        # rubocop: disable RSpec/MultipleExpectations
        it 'sends the set flag to Slack' do
          args = %w[set foo 10]
          command = described_class.new(args, options, env_vars)
          expect(command).to receive(:production_channel_id).and_return('production')
          expect(command).to receive(:valid_setting_for_percentage_value?).and_return(true)
          expect(command).to receive(:valid_actors_random_setting?).and_return(true)
          expect(command).to receive(:feature_flag_consistency_check?).and_return(true)
          expect(command).to receive(:production_check?).and_return(true)
          expect(client).to receive(:set_feature)
          expect(command).to receive(:perform_side_effects).with('foo', '10', anything, anything, options)

          command.set
        end
        # rubocop: enable RSpec/MultipleExpectations
      end

      context 'when the channel is not production' do
        let(:slack_channel) { 'not production' }

        it 'aborts with an error explanation response' do
          args = %w[set foo 10]
          command = described_class.new(args, options, env_vars)
          expect(client).not_to receive(:set_feature)

          command.set
        end
      end
      # rubocop: enable RSpec/NestedGroups
    end

    context 'when the channel is not production and the target environment is not production' do
      let(:client) { instance_double('client') }
      let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
      let(:feature) { instance_double('feature', name: 'foo', state: 'conditional', gates: gates) }
      let(:options) { { staging: true } }
      let(:env_vars) do
        {
          'CHAT_CHANNEL' => 'not production',
          'GITLAB_TOKEN' => '123',
          'GITLAB_USER_LOGIN' => 'alice',
          'GRAFANA_TOKEN' => 'some-grafana-token',
          'SLACK_TOKEN' => '456'
        }
      end

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(client)
        allow(client).to receive(:set_feature).and_return(feature)
      end

      it 'sends the set flag to non-production Slack' do
        args = %w[set foo 10]
        command = described_class.new(args, options, env_vars)
        expect(command).to receive(:valid_setting_for_percentage_value?).and_return(true)
        expect(command).to receive(:valid_actors_random_setting?).and_return(true)
        expect(command).to receive(:production_check?).and_return(true)
        expect(client).to receive(:set_feature)
        expect(command).to receive(:perform_side_effects).with('foo', '10', anything, anything, options)

        command.set
      end
    end

    context 'when specifying feature name with backticks' do
      let(:command_args) { ['set', feature_name, '0'] }
      let(:command_opts) { default_opts }
      let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 0 }] }
      let(:log_feature_toggle_fields) { { feature_name: expected_feature_name, feature_value: '0', feature_scope_actors: 'false' } }
      let(:set_feature_params) do
        [
          expected_feature_name,
          '0',
          {
            project: nil,
            group: nil,
            feature_group: nil,
            namespace: nil,
            user: nil,
            repository: nil,
            actors: false
          }
        ]
      end

      include_context 'with feature name tables with backticks'
      with_them do
        it_behaves_like 'valid feature flag update'
      end
    end
  end
  # describe '#set'

  describe '#list' do
    it 'sends the enabled and disabled features to Slack' do
      command = described_class.new(
        %w[list],
        {},
        'GITLAB_TOKEN' => '123',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_STAGING_REF_TOKEN' => '654',
        'SLACK_TOKEN' => '456',
        'CHAT_CHANNEL' => 'foo'
      )

      message = instance_double('message')

      expect(command)
        .to receive(:attachment_fields_per_state)
        .and_return([[], []])

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(message)

      expect(message).to receive(:send)

      expect(command.list).to be_nil # returns nil to avoid unnecessary response message
    end
  end

  describe '#delete' do
    let(:log_feature_toggle_params) { %w[foo deleted] }
    let(:issue) { instance_double('GitLab::Issue') }
    let(:client) { instance_double('client') }
    let(:message) { instance_double('message') }
    let(:environment) { command.environments.first }

    let(:command) do
      described_class.new(
        %w[delete foo],
        {},
        'GITLAB_TOKEN' => '123',
        'GITLAB_USER_LOGIN' => 'alice',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_STAGING_REF_TOKEN' => '654',
        'SLACK_TOKEN' => '456',
        'CHAT_CHANNEL' => 'foo'
      )
    end

    before do
      allow(Chatops::Gitlab::Client).to receive(:new).and_return(client)
      allow(client).to receive(:delete_feature)
      allow(Chatops::Slack::Message).to receive(:new).and_return(message)
      allow(message).to receive(:send)
      allow(command).to receive(:log_feature_toggle)
      allow(command).to receive(:send_feature_toggle_event)
      allow(command).to receive(:production_channel_id).and_return(command.env['CHAT_CHANNEL'])
    end

    it 'tells the client to delete the feature flag' do
      expect(Chatops::Gitlab::Client).to receive(:new).with(token: '123', host: 'gitlab.com').and_return(client)
      expect(client).to receive(:delete_feature).with('foo')

      command.delete
    end

    it 'returns nil to avoid unnecessary response message' do
      expect(command.delete).to be_nil
    end

    it 'logs the deletion of the feature flag to chatops' do
      expect(command).to receive(:send_feature_toggle_event).with('foo', 'deleted', environment)

      command.delete
    end

    it 'sends the deleted flag to Slack' do
      expect(Chatops::Slack::Message).to receive(:new).with(token: '456', channel: 'foo').and_return(message)
      expect(message).to receive(:send).with(text: 'Feature flag foo has been removed from gitlab.com!')

      command.delete
    end

    it 'sends the deleted flag to create an issue' do
      expect(command).to receive(:log_feature_toggle).with(*log_feature_toggle_params, environment).and_return(issue)

      command.delete
    end

    context 'when the channel is production and the target environment is production' do
      it 'sends the deleted flag to Slack' do
        command.env['CHAT_CHANNEL'] = 'production'
        expect(environment).to receive(:production?).and_return(true)
        expect(command).to receive(:production_channel_id).at_least(:once).and_return('production')
        expect(command).not_to receive(:wrong_channel_resp)

        command.delete
      end
    end

    context 'when the channel is not production and the target environment is not production' do
      it 'sends the deleted flag to non-production Slack' do
        expect(environment).to receive(:production?).and_return(false)
        expect(command).not_to receive(:production_channel_id)
        expect(command).not_to receive(:wrong_channel_resp)

        command.delete
      end
    end

    context 'when the channel is not production but the target environment is production' do
      it 'aborts with an error explanation response' do
        expect(environment).to receive(:production?).and_return(true)
        expect(command).to receive(:production_channel_id).at_least(:once).and_return('production')
        expect(command).to receive(:wrong_channel_resp).once
        expect(client).not_to receive(:delete_feature)

        command.delete
      end
    end

    context 'when feature name contains backticks' do
      include_context 'with feature name tables with backticks'
      with_them do
        let(:command) do
          described_class.new(
            ['delete', feature_name],
            {},
            'GITLAB_TOKEN' => '123',
            'GITLAB_USER_LOGIN' => 'alice',
            'GITLAB_STAGING_TOKEN' => '321',
            'GITLAB_STAGING_REF_TOKEN' => '654',
            'SLACK_TOKEN' => '456',
            'CHAT_CHANNEL' => 'foo'
          )
        end
        it 'deletes the feature with stripped backticks' do
          expect(Chatops::Gitlab::Client).to receive(:new).with(token: '123', host: 'gitlab.com').and_return(client)
          expect(client).to receive(:delete_feature).with(expected_feature_name)

          command.delete
        end
      end
    end
  end

  describe '#send_feature_details' do
    it 'sends the details of a single feature back to Slack' do
      command = described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => '456')

      feature = Chatops::Gitlab::Feature.new(
        name: 'foo',
        state: 'on',
        gates: [{ 'key' => 'boolean', 'value' => false }]
      )

      message = instance_double('message')

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '123', channel: '456')
        .and_return(message)

      expect(message)
        .to receive(:send)
        .with(a_hash_including(text: 'Hello'))

      environment = command.environments.find(&:production?)
      command.send_feature_details(feature: feature, text: 'Hello', environment: environment)
    end
  end

  describe '#send_feature_toggling_to_qa_channel' do
    let(:issue) do
      instance_double(
        'GitLab::Issue',
        title: 'Issue title',
        web_url: 'http://gitlab.example.org/issues/1'
      )
    end

    shared_examples 'message sent to the relevant Slack QA channel with no pipeline link' do |channel|
      it 'sends a message to the relevant Slack QA channel' do
        message = instance_double('Chatops::Slack::Message', send: nil)
        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: channel)
          .and_return(message)

        environment = command.environments.first
        command.send_feature_toggling_to_qa_channel(issue, environment)
      end

      it 'sends a relevant Slack message' do
        expect_slack_message(blocks: QaMessageBlockMatcher.new(issue, command))

        environment = command.environments.first
        command.send_feature_toggling_to_qa_channel(issue, environment)
      end
    end

    shared_examples 'message sent to the relevant Slack QA channel with pipeline link' do |channel|
      let(:ops_pipeline) { 'https://ops.gitlab.net/gitlab-org/quality/production/-/pipelines/123' }

      it 'sends a message to the relevant Slack QA channel' do
        message = instance_double('Chatops::Slack::Message', send: nil)
        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: channel)
          .and_return(message)

        environment = command.environments.first
        command.send_feature_toggling_to_qa_channel(issue, environment, ops_pipeline)
      end

      it 'sends a relevant Slack message' do
        expect_slack_message(blocks: QaMessageBlockMatcher.new(issue, command, ops_pipeline))

        environment = command.environments.first
        command.send_feature_toggling_to_qa_channel(issue, environment, ops_pipeline)
      end
    end

    context 'when environment is production' do
      let(:username) { 'alice' }
      let(:command) do
        described_class.new(
          [],
          {},
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456',
          'GITLAB_USER_LOGIN' => username
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel with no pipeline link',
        described_class::QA_CHANNELS[described_class::PRODUCTION_HOST]
      )

      include_examples(
        'message sent to the relevant Slack QA channel with pipeline link',
        described_class::QA_CHANNELS[described_class::PRODUCTION_HOST]
      )
    end

    context 'when environment is staging' do
      let(:username) { 'alice' }
      let(:command) do
        described_class.new(
          [],
          { staging: true },
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456',
          'GITLAB_USER_LOGIN' => username
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel with no pipeline link',
        described_class::QA_CHANNELS[described_class::STAGING_HOST]
      )
      include_examples(
        'message sent to the relevant Slack QA channel with pipeline link',
        described_class::QA_CHANNELS[described_class::STAGING_HOST]
      )
    end

    context 'when environment is staging-ref' do
      let(:username) { 'alice' }
      let(:command) do
        described_class.new(
          [],
          { staging_ref: true },
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456',
          'GITLAB_USER_LOGIN' => username
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel with no pipeline link',
        described_class::QA_CHANNELS[described_class::STAGING_REF_HOST]
      )
      include_examples(
        'message sent to the relevant Slack QA channel with pipeline link',
        described_class::QA_CHANNELS[described_class::STAGING_REF_HOST]
      )
    end

    context 'when environment is pre' do
      let(:command) do
        described_class.new(
          [],
          { pre: true },
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456'
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel with no pipeline link',
        described_class::QA_CHANNELS[described_class::PRE_HOST]
      )
    end

    context 'when environment is dev' do
      let(:command) do
        described_class.new(
          [],
          { dev: true },
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456'
        )
      end

      it 'does not send a message' do
        expect(Chatops::Slack::Message)
          .not_to receive(:new)

        environment = command.environments.find(&:dev?)
        command.send_feature_toggling_to_qa_channel(issue, environment)
      end
    end
  end

  describe '#attachment_fields_per_state' do
    it 'returns attachment fields grouped per state ' do
      command = described_class
        .new([], { match: 'foo' }, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321', 'GITLAB_STAGING_REF_TOKEN' => '654')

      feature = Chatops::Gitlab::Feature.new(
        name: 'foo',
        state: 'on',
        gates: [{ 'key' => 'boolean', 'value' => false }]
      )

      collection = instance_double('collection', per_state: [[], [feature]])

      expect(Chatops::Gitlab::FeatureCollection)
        .to receive(:new)
        .with(token: '123', match: 'foo', host: 'gitlab.com')
        .and_return(collection)

      environment = command.environments.find(&:production?)

      expect(command.attachment_fields_per_state(environment))
        .to eq([[], [feature.to_attachment_field]])
    end
  end

  describe '#gitlab_token' do
    context 'when using dev' do
      it 'returns the value of GITLAB_DEV_TOKEN' do
        command = described_class.new(
          [],
          { dev: true },
          'GITLAB_DEV_TOKEN' => '123',
          'GITLAB_TOKEN' => '456',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654'
        )

        expect(command.environments.count).to eq(1)
        expect(command.environments.first).to be_dev
        expect(command.environments.first.gitlab_token).to eq('123')
      end
    end

    context 'when using pre' do
      it 'returns the value of GITLAB_PRE_TOKEN' do
        command = described_class.new(
          [],
          { pre: true },
          'GITLAB_PRE_TOKEN' => '123',
          'GITLAB_TOKEN' => '456',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654'
        )

        expect(command.environments.count).to eq(1)
        expect(command.environments.first).to be_pre
        expect(command.environments.first.gitlab_token).to eq('123')
      end
    end

    context 'when using staging-ref' do
      it 'returns the value of GITLAB_STAGING_REF_TOKEN' do
        command = described_class.new(
          [],
          { staging_ref: true },
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654',
          'GITLAB_TOKEN' => '456'
        )

        expect(command.environments.count).to eq(1)
        expect(command.environments.first).to be_staging_ref
        expect(command.environments.first.gitlab_token).to eq('654')
      end
    end

    context 'when using staging' do
      it 'returns the value of GITLAB_STAGING_TOKEN' do
        command = described_class.new(
          [],
          { staging: true },
          'GITLAB_STAGING_TOKEN' => '123',
          'GITLAB_STAGING_REF_TOKEN' => '654',
          'GITLAB_TOKEN' => '456'
        )

        expect(command.environments.count).to eq(1)
        expect(command.environments.first).to be_staging
        expect(command.environments.first.gitlab_token).to eq('123')
      end
    end

    context 'when using production' do
      it 'returns the value of GITLAB_TOKEN' do
        command = described_class.new(
          [],
          {},
          'GITLAB_STAGING_TOKEN' => '123',
          'GITLAB_STAGING_REF_TOKEN' => '654',
          'GITLAB_TOKEN' => '456'
        )

        expect(command.gitlab_token).to eq('456')
      end
    end

    context 'when using multi-environments' do
      # rubocop:disable RSpec/MultipleExpectations
      it 'returns the value of GITLAB_DEV_TOKEN' do
        command = described_class.new(
          [],
          { dev: true, staging: true, production: true },
          'GITLAB_DEV_TOKEN' => '123',
          'GITLAB_TOKEN' => '456',
          'GITLAB_STAGING_TOKEN' => '321'
        )

        expect(command.environments.count).to eq(3)
        expect(command.environments[0]).to be_dev
        expect(command.environments[0].gitlab_token).to eq('123')
        expect(command.environments[1]).to be_staging
        expect(command.environments[1].gitlab_token).to eq('321')
        expect(command.environments[2]).to be_production
        expect(command.environments[2].gitlab_token).to eq('456')
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
  end

  describe '#gitlab_host' do
    context 'when using dev' do
      it 'returns dev.gitlab.org' do
        command = described_class.new([], dev: true)

        expect(command.environments.count).to eq(1)
        expect(command.environments.first.gitlab_host).to eq('dev.gitlab.org')
      end
    end

    context 'when using pre' do
      it 'returns pre.gitlab.com' do
        command = described_class.new([], pre: true)

        expect(command.environments.count).to eq(1)
        expect(command.environments.first.gitlab_host).to eq('pre.gitlab.com')
      end
    end

    context 'when using staging-ref' do
      it 'returns staging-ref.gitlab.com' do
        command = described_class.new([], staging_ref: true)

        expect(command.environments.count).to eq(1)
        expect(command.environments.first.gitlab_host).to eq('staging-ref.gitlab.com')
      end
    end

    context 'when using staging' do
      it 'returns staging.gitlab.com' do
        command = described_class.new([], staging: true)

        expect(command.environments.count).to eq(1)
        expect(command.environments.first.gitlab_host).to eq('staging.gitlab.com')
      end
    end

    context 'when using production' do
      it 'returns gitlab.com' do
        command = described_class.new

        expect(command.environments.count).to eq(1)
        expect(command.environments.first.gitlab_host).to eq('gitlab.com')
      end
    end
  end

  describe '#log_feature_toggle' do
    context 'with all required variables set' do
      it 'creates a closed issue' do
        command = described_class.new(
          [],
          {},
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654'
        )

        environment = command.environments.find(&:production?)
        client = instance_double(Chatops::Gitlab::Client)
        issue = instance_double('issue', project_id: 1, iid: 2)

        expect(Chatops::GitlabEnvironments::Environment.production)
          .to receive(:api_client)
          .and_return(client)

        expect(client)
          .to receive(:create_issue)
          .with(
            described_class::LOG_PROJECT,
            an_instance_of(String),
            labels: 'host::gitlab.com, change',
            description: an_instance_of(String)
          )
          .and_return(issue)
        expect(client).to receive(:close_issue).with(1, 2)

        expect(command.log_feature_toggle('foo', 'bar', environment)).to eq(issue)
      end

      it 'adds a label when incidents are ignored' do
        command = described_class.new(
          [],
          { ignore_production_check: true },
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654'
        )

        environment = command.environments.find(&:production?)
        client = instance_double(Chatops::Gitlab::Client)
        issue = instance_double('issue', project_id: 1, iid: 2)

        expect(Chatops::GitlabEnvironments::Environment.production)
          .to receive(:api_client)
          .and_return(client)

        expect(client)
          .to receive(:create_issue)
          .with(
            described_class::LOG_PROJECT,
            an_instance_of(String),
            labels: 'host::gitlab.com, change, Production check ignored',
            description: an_instance_of(String)
          )
          .and_return(issue)
        expect(client).to receive(:close_issue).with(1, 2)

        expect(command.log_feature_toggle('foo', 'bar', environment)).to eq(issue)
      end
    end
  end

  describe '#production_check?' do
    let(:command) do
      described_class.new(
        [],
        {},
        'GITLAB_TOKEN' => 'foo',
        'SLACK_TOKEN' => '123',
        'CHAT_CHANNEL' => '456',
        'GITLAB_OPS_TOKEN' => '789',
        'CI_JOB_TOKEN' => 'abc',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_STAGING_REF_TOKEN' => '654'
      )
    end
    let(:message) { instance_double('Chatops::Slack::Message', send: nil) }
    # Simulate a `Gitlab::ObjectifiedHash` for a `update_or_create_deployment` response
    let(:trigger_resp) { instance_double('trigger response', id: '123') }
    let(:slack_msg) { instance_spy(Chatops::Slack::Message) }

    it 'checks status of job in pipeline' do
      client = instance_double(Chatops::Gitlab::Client)

      allow(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '789', host: 'ops.gitlab.net')
        .and_return(client)

      allow(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '123', channel: '456')
        .and_return(slack_msg)

      allow(slack_msg).to receive(:send).with(text: 'Production check initiated, this may take up to 300 seconds ...')

      allow(command).to receive(:run_trigger).with(
        CHECK_PRODUCTION: 'true',
        FAIL_IF_NOT_SAFE: 'true',
        SKIP_DEPLOYMENT_CHECK: 'true',
        PRODUCTION_CHECK_SCOPE: 'feature_flag'
      ).and_return(trigger_resp)

      allow(client)
        .to receive(:pipeline_jobs)
        .with('gitlab-org/release/tools', '123')
        .and_return(
          instance_double(
            Gitlab::PaginatedResponse,
            auto_paginate: [
              instance_double('gitlab API response', name: 'auto_deploy:check_production', status: 'success'),
              instance_double('gitlab API response', name: 'another-job')
            ]
          )
        )

      environment = command.environments.first
      expect(command.production_check?(environment)).to eq(true)
    end

    shared_examples 'triggers a production check' do |production_check_job_status:, result:|
      it 'sends a Slack notification and triggers a pipline' do
        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: '456')
          .and_return(slack_msg)
        expect(slack_msg).to receive(:send).with(text: 'Production check initiated, this may take up to 300 seconds ...')
        expect(command).to receive(:run_trigger).with(
          CHECK_PRODUCTION: 'true',
          FAIL_IF_NOT_SAFE: 'true',
          SKIP_DEPLOYMENT_CHECK: 'true',
          PRODUCTION_CHECK_SCOPE: 'feature_flag'
        ).and_return(trigger_resp)
        expect(command).to receive(:production_check_status).with('123')
          .and_return(production_check_job_status)

        environment = command.environments.first
        expect(command.production_check?(environment)).to eq(result)
      end
    end

    context 'when there are no failing checks' do
      it_behaves_like 'triggers a production check',
                      production_check_job_status: 'success',
                      result: true
    end

    context 'when there is a failing checks' do
      it_behaves_like 'triggers a production check',
                      production_check_job_status: 'failed',
                      result: false
    end

    context 'when there are incidents when setting a staging feature flag' do
      let(:command) do
        described_class.new(
          [],
          { staging: true },
          'CHAT_CHANNEL' => '456',
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321',
          'GITLAB_STAGING_REF_TOKEN' => '654'
        )
      end

      it 'returns true when the environment is staging' do
        expect(command).not_to receive(:run_trigger)

        environment = command.environments.find(&:staging?)
        expect(command.production_check?(environment)).to eq(true)
      end
    end
  end
end

# RSpec argument matcher for verifying the complex `block` Hash passed to
# `Slack::Message#send` from the described class
class QaMessageBlockMatcher
  def initialize(issue, command = nil, trigger_tests_response = nil)
    @issue = issue
    @command = command
    @trigger_tests_response = trigger_tests_response
  end

  def ===(other)
    markdown_text = @command.text_for_slack_message(@trigger_tests_response, @issue)

    other.first[:text][:text] == markdown_text
  end
end
