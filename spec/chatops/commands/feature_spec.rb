# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Feature do
  shared_examples 'invalid feature flag update' do
    let(:error_message) { /Unable to proceed due to inconsistent feature flag status. When the flag on production is turned on, staging should be on too./ }
    let(:command_args) { %w[set foo] + [value] }
    let(:command_opts) { { project: nil, group: nil, user: 'myuser' } }
    let(:log_feature_toggle_params) { ['foo', value] }
    let(:feature_enabled) { false }
    let(:set_feature_params) do
      [
        'foo',
        value,
        {
          project: nil,
          group: nil,
          user: 'myuser',
          actors: nil
        }
      ]
    end
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
        'GITLAB_TOKEN' => '123',
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_USER_LOGIN' => 'alice'
      }
      command = described_class.new(command_args, command_opts, command_envs)

      staging_feature_command = instance_double('Chatops::Commands::Feature')

      expect(described_class)
        .to receive(:new)
        .with(%w[get foo], command_opts.merge(staging: true), command_envs)
        .and_return(staging_feature_command)

      expect(command)
        .to receive(:production_check?)
        .and_return(true)

      expect(staging_feature_command)
        .to receive(:get_feature).with('foo')
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
        'GITLAB_TOKEN' => '123',
        'GRAFANA_TOKEN' => 'some-grafana-token',
        'GITLAB_STAGING_TOKEN' => '321',
        'GITLAB_USER_LOGIN' => 'alice'
      }
      command = described_class.new(command_args, command_opts, command_envs)

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
        .to receive(:get_feature).with('foo')
        .and_return(feature)

      allow(feature)
        .to receive(:enabled?)
        .and_return(feature_enabled)

      expect(command)
        .to receive(:production_check?)
        .and_return(true)

      issue = instance_double('GitLab::Issue')
      expect(command)
        .to receive(:log_feature_toggle)
        .with(*log_feature_toggle_params)
        .and_return(issue)

      expect(command)
        .to receive(:send_feature_toggle_event)
        .with(*log_feature_toggle_params)

      annotate = instance_double('annotate')

      expect(Chatops::Grafana::Annotate)
        .to receive(:new)
        .with(token: 'some-grafana-token')
        .and_return(annotate)

      expect(annotate)
        .to receive(:annotate!)
        .with(
          "alice set feature flag foo to #{log_feature_toggle_params[1]}",
          tags: tag_env + ['feature-flag', 'foo']
        )

      expect(command)
        .to receive(:send_feature_details)
        .with(
          feature: an_instance_of(Chatops::Gitlab::Feature),
          text: 'The feature flag value has been updated!'
        )

      expect(command)
        .to receive(:send_feature_toggling_to_qa_channel)
        .with(issue)

      command.set
    end
  end
  # rubocop: enable RSpec/ExampleLength
  # rubocop: enable RSpec/MultipleExpectations

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
          a_hash_including(staging: true, dev: false, ops: false, pre: false),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --staging])
    end

    it 'supports a --dev option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature list],
          a_hash_including(staging: false, dev: true, ops: false, pre: false),
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
          a_hash_including(staging: false, dev: false, ops: true, pre: false),
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
          a_hash_including(staging: false, dev: false, ops: false, pre: true),
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
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321')
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
      it 'sends the details of the feature to Slack' do
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321')
        collection = instance_double('collection')
        feature = instance_double('feature')

        expect(Chatops::Gitlab::FeatureCollection)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(collection)

        expect(collection)
          .to receive(:find_by_name)
          .with('foo')
          .and_return(feature)

        expect(command)
          .to receive(:send_feature_details)
          .with(feature: feature)

        command.get
      end
    end
  end

  describe '#set' do
    context 'when not specifying a feature name' do
      it 'returns an error message' do
        command = described_class.new(%w[set])

        expect(command.set).to match(/You must specify the name of the feature/)
      end
    end

    context 'when not specifying a feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo])

        expect(command.set).to match(/You must specify the name of the feature/)
      end
    end

    context 'when specifying an invalid feature value' do
      it 'returns an error message' do
        command = described_class.new(%w[set foo bar])

        expect(command.set).to match(/The value "bar" is invalid/)
      end
    end

    context 'when using valid arguments' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo 10] }
        let(:command_opts) { {} }
        let(:gates) { [{ 'key' => 'percentage_of_time', 'value' => 10 }] }
        let(:log_feature_toggle_params) { %w[foo 10] }
        let(:set_feature_params) do
          [
            'foo',
            '10',
            {
              project: nil,
              group: nil,
              user: nil,
              actors: nil
            }
          ]
        end
      end
    end

    context 'when using a project feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { { project: 'gitlab-org/gitaly', group: nil, user: nil } }
        let(:gates) { [{ 'project' => 'gitlab-org/gitaly', 'value' => true }] }
        let(:log_feature_toggle_params) { %w[foo true] }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: 'gitlab-org/gitaly',
              group: nil,
              user: nil,
              actors: nil
            }
          ]
        end
      end
    end

    context 'when using a group feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { { project: nil, group: 'gitlab-org', user: nil } }
        let(:gates) { [{ 'group' => 'gitlab-org', 'value' => true }] }
        let(:log_feature_toggle_params) { %w[foo true] }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: 'gitlab-org',
              user: nil,
              actors: nil
            }
          ]
        end
      end
    end

    context 'when using a user feature gate' do
      include_examples 'valid feature flag update' do
        let(:command_args) { %w[set foo true] }
        let(:command_opts) { { project: nil, group: nil, user: 'myuser' } }
        let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
        let(:log_feature_toggle_params) { %w[foo true] }
        let(:set_feature_params) do
          [
            'foo',
            'true',
            {
              project: nil,
              group: nil,
              user: 'myuser',
              actors: nil
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
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update'
        end

        context 'when setting a percentage value' do
          let(:value) { '10' }
          let(:gates) { [{ 'value' => 10, 'key' => 'percentage_of_time' }] }

          include_examples 'invalid feature flag update'
        end

        context 'when the ignore_feature_flag_consistency_check is true' do
          let(:command_args) { %w[set foo true] }
          let(:command_opts) { { project: nil, group: nil, user: 'myuser', ignore_feature_flag_consistency_check: true } }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
          let(:log_feature_toggle_params) { %w[foo true] }
          let(:set_feature_params) do
            [
              'foo',
              'true',
              {
                project: nil,
                group: nil,
                user: 'myuser',
                actors: nil
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
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update' do
            let(:feature) { nil }
          end
        end
      end
    end

    context 'when the flag is turned on in production' do
      let(:command_opts) { { project: nil, group: nil, user: 'myuser', staging: true } }

      context 'when turning off in staging' do
        context 'when setting a boolean value' do
          let(:value) { 'true' }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }

          include_examples 'invalid feature flag update'
        end

        context 'when setting a percentage value' do
          let(:value) { '10' }
          let(:gates) { [{ 'value' => 10, 'key' => 'percentage_of_time' }] }

          include_examples 'invalid feature flag update'
        end

        context 'when the ignore_feature_flag_consistency_check is true' do
          let(:command_args) { %w[set foo true] }
          let(:command_opts) { { project: nil, group: nil, user: 'myuser', ignore_feature_flag_consistency_check: true, staging: true } }
          let(:gates) { [{ 'user' => 'myuser', 'value' => true }] }
          let(:log_feature_toggle_params) { %w[foo true] }
          let(:set_feature_params) do
            [
              'foo',
              'true',
              {
                project: nil,
                group: nil,
                user: 'myuser',
                actors: nil
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

    context 'when the feature flag does not exist in production' do
      let(:command_opts) { { project: nil, group: nil, user: 'myuser', staging: true } }

      context 'when turning on staging' do
        context 'when setting a boolean value' do
          let(:value) { 'true' }
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
        command =
          described_class.new(%w[set foo 10], {}, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321')

        expect(command).to receive(:production_check?).and_return(false)

        expect(command.set).to match(/production check failure/)
      end
    end
  end

  describe '#list' do
    it 'sends the enabled and disabled features to Slack' do
      command = described_class.new(
        %w[list],
        {},
        'GITLAB_TOKEN' => '123',
        'GITLAB_STAGING_TOKEN' => '321',
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

      command.list
    end
  end

  describe '#delete' do
    it 'sends the deleted flag to Slack' do
      command = described_class.new(
        %w[delete foo],
        {},
        'GITLAB_TOKEN' => '123',
        'GITLAB_STAGING_TOKEN' => '321',
        'SLACK_TOKEN' => '456',
        'CHAT_CHANNEL' => 'foo'
      )

      client = instance_double('client')
      expect(Chatops::Gitlab::Client)
        .to receive(:new)
        .with(token: '123', host: 'gitlab.com')
        .and_return(client)

      expect(client)
        .to receive(:delete_feature)
        .with('foo')

      message = instance_double('message')
      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '456', channel: 'foo')
        .and_return(message)

      expect(message).to receive(:send)
        .with(text: 'Feature flag foo has been removed from gitlab.com!')

      expect(command)
        .to receive(:send_feature_toggle_event)
        .with('foo', 'deleted')

      command.delete
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

      command.send_feature_details(feature: feature, text: 'Hello')
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

    shared_examples 'message sent to the relevant Slack QA channel' do |channel|
      it 'sends a message to the relevant Slack QA channel' do
        message = instance_double('Chatops::Slack::Message', send: nil)
        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: channel)
          .and_return(message)

        command.send_feature_toggling_to_qa_channel(issue)
      end

      it 'sends a relevant Slack message' do
        expect_slack_message(blocks: QaMessageBlockMatcher.new(issue))

        command.send_feature_toggling_to_qa_channel(issue)
      end
    end

    context 'when environment is production' do
      let(:command) do
        described_class.new(
          [],
          {},
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456'
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel',
        described_class::QA_CHANNELS[described_class::PRODUCTION_HOST]
      )
    end

    context 'when environment is staging' do
      let(:command) do
        described_class.new(
          [],
          { staging: true },
          'SLACK_TOKEN' => '123',
          'CHAT_CHANNEL' => '456'
        )
      end

      include_examples(
        'message sent to the relevant Slack QA channel',
        described_class::QA_CHANNELS[described_class::STAGING_HOST]
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
        'message sent to the relevant Slack QA channel',
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

        command.send_feature_toggling_to_qa_channel(issue)
      end
    end
  end

  describe '#attachment_fields_per_state' do
    it 'returns attachment fields grouped per state ' do
      command = described_class
        .new([], { match: 'foo' }, 'GITLAB_TOKEN' => '123', 'GITLAB_STAGING_TOKEN' => '321')

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

      expect(command.attachment_fields_per_state)
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
          'GITLAB_STAGING_TOKEN' => '321'
        )

        expect(command.gitlab_token).to eq('123')
      end
    end

    context 'when using pre' do
      it 'returns the value of GITLAB_PRE_TOKEN' do
        command = described_class.new(
          [],
          { pre: true },
          'GITLAB_PRE_TOKEN' => '123',
          'GITLAB_TOKEN' => '456',
          'GITLAB_STAGING_TOKEN' => '321'
        )

        expect(command.gitlab_token).to eq('123')
      end
    end

    context 'when using staging' do
      it 'returns the value of GITLAB_STAGING_TOKEN' do
        command = described_class.new(
          [],
          { staging: true },
          'GITLAB_STAGING_TOKEN' => '123',
          'GITLAB_TOKEN' => '456'
        )

        expect(command.gitlab_token).to eq('123')
      end
    end

    context 'when using production' do
      it 'returns the value of GITLAB_TOKEN' do
        command = described_class.new(
          [],
          {},
          'GITLAB_STAGING_TOKEN' => '123',
          'GITLAB_TOKEN' => '456'
        )

        expect(command.gitlab_token).to eq('456')
      end
    end
  end

  describe '#gitlab_host' do
    context 'when using dev' do
      it 'returns dev.gitlab.org' do
        command = described_class.new([], dev: true)

        expect(command.gitlab_host).to eq('dev.gitlab.org')
      end
    end

    context 'when using pre' do
      it 'returns pre.gitlab.com' do
        command = described_class.new([], pre: true)

        expect(command.gitlab_host).to eq('pre.gitlab.com')
      end
    end

    context 'when using staging' do
      it 'returns staging.gitlab.com' do
        command = described_class.new([], staging: true)

        expect(command.gitlab_host).to eq('staging.gitlab.com')
      end
    end

    context 'when using production' do
      it 'returns gitlab.com' do
        command = described_class.new

        expect(command.gitlab_host).to eq('gitlab.com')
      end
    end
  end

  describe '#log_feature_toggle' do
    context 'without the GITLAB_USER_LOGIN variable' do
      it 'raises KeyError' do
        command = described_class.new

        expect { command.log_feature_toggle('foo', 'bar') }
          .to raise_error(KeyError)
      end
    end

    context 'without the GITLAB_TOKEN variable' do
      it 'raises KeyError' do
        command = described_class.new([], {}, 'GITLAB_USER_LOGIN' => 'alice')

        expect { command.log_feature_toggle('foo', 'bar') }
          .to raise_error(KeyError)
      end
    end

    context 'with all required variables set' do
      it 'creates a closed issue' do
        command = described_class.new(
          [],
          {},
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321'
        )

        client = instance_double(Chatops::Gitlab::Client)
        issue = instance_double('issue', project_id: 1, iid: 2)

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'foo', host: 'gitlab.com')
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

        expect(command.log_feature_toggle('foo', 'bar')).to eq(issue)
      end

      it 'adds a label when incidents are ignored' do
        command = described_class.new(
          [],
          { ignore_production_check: true },
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321'
        )

        client = instance_double(Chatops::Gitlab::Client)
        issue = instance_double('issue', project_id: 1, iid: 2)

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'foo', host: 'gitlab.com')
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

        expect(command.log_feature_toggle('foo', 'bar')).to eq(issue)
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
        'GITLAB_STAGING_TOKEN' => '321'
      )
    end
    let(:message) { instance_double('Chatops::Slack::Message', send: nil) }
    # Simulate a `Gitlab::ObjectifiedHash` for a `update_or_create_deployment` response
    let(:trigger_resp) { instance_double('trigger response', id: '123') }
    let(:slack_msg) { instance_spy(Chatops::Slack::Message) }

    shared_examples 'triggers a production check' do |pipeline_status:, result:|
      it 'sends a Slack notification and triggers a pipline' do
        expect(Chatops::Slack::Message)
          .to receive(:new)
          .with(token: '123', channel: '456')
          .and_return(slack_msg)
        expect(slack_msg).to receive(:send).with(text: 'Production check initiated, this may take up to 300 seconds ...')
        expect(command).to receive(:run_trigger).with(
          CHECK_PRODUCTION: 'true',
          FAIL_IF_NOT_SAFE: 'true',
          SKIP_DEPLOYMENT_CHECK: 'true'
        ).and_return(trigger_resp)
        expect(command).to receive(:pipeline_status).with('123')
          .and_return(pipeline_status)

        expect(command.production_check?).to eq(result)
      end
    end

    context 'when there are no failing checks' do
      it_behaves_like 'triggers a production check',
                      pipeline_status: 'success',
                      result: true
    end

    context 'when there is a failing checks' do
      it_behaves_like 'triggers a production check',
                      pipeline_status: 'failed',
                      result: false
    end

    context 'when there are incidents when setting a staging feature flag' do
      let(:command) do
        described_class.new(
          [],
          { staging: true },
          'GITLAB_TOKEN' => 'foo',
          'GITLAB_STAGING_TOKEN' => '321'
        )
      end

      it 'returns true when the environment is staging' do
        expect(command).not_to receive(:run_trigger)

        expect(command.production_check?).to eq(true)
      end
    end
  end
end

# RSpec argument matcher for verifying the complex `block` Hash passed to
# `Slack::Message#send` from the described class
class QaMessageBlockMatcher
  def initialize(issue)
    @issue = issue
  end

  def ===(other)
    json = other.to_json

    json.include?("<#{@issue.web_url}|#{@issue.title}>")
  end
end
