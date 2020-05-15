# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Feature do
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
          a_hash_including(staging: true, dev: false, ops: false),
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
          a_hash_including(staging: false, dev: true, ops: false),
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
          a_hash_including(staging: false, dev: false, ops: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature list --ops])
    end

    it 'supports a --ignore-incidents option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[feature set foo true],
          a_hash_including(ignore_incidents: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[feature set foo true --ignore-incidents])
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
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123')
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
        command = described_class.new(%w[get foo], {}, 'GITLAB_TOKEN' => '123')
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
      # rubocop: disable RSpec/ExampleLength
      # rubocop: disable RSpec/MultipleExpectations
      it 'updates the feature flag' do
        command = described_class
          .new(%w[set foo 10], {},
               'GITLAB_TOKEN' => '123',
               'GRAFANA_TOKEN' => 'some-grafana-token',
               'GITLAB_USER_LOGIN' => 'alice')

        client = instance_double('Chatops::Gitlab::Client')
        feature = instance_double(
          'feature',
          name: 'foo',
          state: 'conditional',
          gates: [{ 'key' => 'percentage_of_time', 'value' => 10 }]
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(client)

        expect(client)
          .to receive(:set_feature)
          .with('foo', '10', project: nil, group: nil, user: nil, actors: nil)
          .and_return(feature)

        expect(command)
          .to receive(:ongoing_incidents?)
          .and_return(false)

        expect(command)
          .to receive(:send_feature_details)
          .with(
            feature: an_instance_of(Chatops::Gitlab::Feature),
            text: 'The feature flag value has been updated!'
          )

        annotate = instance_double('annotate')
        expect(Chatops::Grafana::Annotate)
          .to receive(:new)
          .with(token: 'some-grafana-token')
          .and_return(annotate)

        expect(annotate)
          .to receive(:annotate!)
          .with(
            'alice set feature flag foo to 10',
            tags: ['gprd', 'feature-flag', 'foo']
          )

        expect(command).to receive(:log_feature_toggle).with('foo', '10')

        command.set
      end
      # rubocop: enable RSpec/ExampleLength
      # rubocop: enable RSpec/MultipleExpectations
    end

    context 'when using a project feature gate' do
      # rubocop: disable RSpec/ExampleLength
      # rubocop: disable RSpec/MultipleExpectations
      it 'updates the feature flag' do
        command = described_class
          .new(%w[set foo true],
               { project: 'gitlab-org/gitaly', group: nil, user: nil },
               'GITLAB_TOKEN' => '123',
               'GRAFANA_TOKEN' => 'some-grafana-token',
               'GITLAB_USER_LOGIN' => 'alice')

        client = instance_double('Chatops::Gitlab::Client')
        feature = instance_double(
          'feature',
          name: 'foo',
          state: 'conditional',
          gates: [{ 'project' => 'gitlab-org/gitaly', 'value' => true }]
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(client)

        expect(client)
          .to receive(:set_feature)
          .with('foo', 'true',
                project: 'gitlab-org/gitaly',
                group: nil,
                user: nil,
                actors: nil)
          .and_return(feature)

        expect(command)
          .to receive(:ongoing_incidents?)
          .and_return(false)

        expect(command)
          .to receive(:send_feature_details)
          .with(
            feature: an_instance_of(Chatops::Gitlab::Feature),
            text: 'The feature flag value has been updated!'
          )

        expect(command).to receive(:log_feature_toggle).with('foo', 'true')

        annotate = instance_double('annotate')

        expect(Chatops::Grafana::Annotate)
          .to receive(:new)
          .with(token: 'some-grafana-token')
          .and_return(annotate)

        expect(annotate)
          .to receive(:annotate!)
          .with(
            'alice set feature flag foo to true',
            tags: ['gprd', 'feature-flag', 'foo']
          )
        command.set
      end
      # rubocop: enable RSpec/ExampleLength
      # rubocop: enable RSpec/MultipleExpectations
    end

    context 'when using a group feature gate' do
      # rubocop: disable RSpec/ExampleLength
      # rubocop: disable RSpec/MultipleExpectations
      it 'updates the feature flag' do
        command = described_class
          .new(%w[set foo true],
               { project: nil, group: 'gitlab-org', user: nil },
               'GITLAB_TOKEN' => '123',
               'GRAFANA_TOKEN' => 'some-grafana-token',
               'GITLAB_USER_LOGIN' => 'alice')

        client = instance_double('Chatops::Gitlab::Client')
        feature = instance_double(
          'feature',
          name: 'foo',
          state: 'conditional',
          gates: [{ 'group' => 'gitlab-org', 'value' => true }]
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(client)

        expect(client)
          .to receive(:set_feature)
          .with('foo', 'true',
                project: nil,
                group: 'gitlab-org',
                user: nil,
                actors: nil)
          .and_return(feature)

        expect(command)
          .to receive(:ongoing_incidents?)
          .and_return(false)

        expect(command)
          .to receive(:send_feature_details)
          .with(
            feature: an_instance_of(Chatops::Gitlab::Feature),
            text: 'The feature flag value has been updated!'
          )

        annotate = instance_double('annotate')

        expect(Chatops::Grafana::Annotate)
          .to receive(:new)
          .with(token: 'some-grafana-token')
          .and_return(annotate)

        expect(annotate)
          .to receive(:annotate!)
          .with(
            'alice set feature flag foo to true',
            tags: ['gprd', 'feature-flag', 'foo']
          )

        expect(command).to receive(:log_feature_toggle).with('foo', 'true')

        command.set
      end
      # rubocop: enable RSpec/ExampleLength
      # rubocop: enable RSpec/MultipleExpectations
    end

    context 'when using a user feature gate' do
      # rubocop: disable RSpec/ExampleLength
      # rubocop: disable RSpec/MultipleExpectations
      it 'updates the feature flag' do
        command = described_class
          .new(%w[set foo true],
               { project: nil, group: nil, user: 'myuser' },
               'GITLAB_TOKEN' => '123',
               'GRAFANA_TOKEN' => 'some-grafana-token',
               'GITLAB_USER_LOGIN' => 'alice')

        client = instance_double('Chatops::Gitlab::Client')
        feature = instance_double(
          'feature',
          name: 'foo',
          state: 'conditional',
          gates: [{ 'user' => 'myuser', 'value' => true }]
        )

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123', host: 'gitlab.com')
          .and_return(client)

        expect(client)
          .to receive(:set_feature)
          .with('foo', 'true', project: nil,
                               group: nil,
                               user: 'myuser',
                               actors: nil)
          .and_return(feature)

        expect(command)
          .to receive(:ongoing_incidents?)
          .and_return(false)

        expect(command)
          .to receive(:send_feature_details)
          .with(
            feature: an_instance_of(Chatops::Gitlab::Feature),
            text: 'The feature flag value has been updated!'
          )

        expect(command).to receive(:log_feature_toggle).with('foo', 'true')

        annotate = instance_double('annotate')

        expect(Chatops::Grafana::Annotate)
          .to receive(:new)
          .with(token: 'some-grafana-token')
          .and_return(annotate)

        expect(annotate)
          .to receive(:annotate!)
          .with(
            'alice set feature flag foo to true',
            tags: ['gprd', 'feature-flag', 'foo']
          )
        command.set
      end
      # rubocop: enable RSpec/ExampleLength
      # rubocop: enable RSpec/MultipleExpectations
    end

    context 'when there is an ongoing incident' do
      it 'does not allow changing the feature flag state' do
        command =
          described_class.new(%w[set foo 10], {}, 'GITLAB_TOKEN' => '123')

        expect(command).to receive(:ongoing_incidents?).and_return(true)

        expect(command.set).to match(/as one or more production incidents/)
      end
    end
  end

  describe '#list' do
    it 'sends the enabled and disabled features to Slack' do
      command = described_class.new(
        %w[list],
        {},
        'GITLAB_TOKEN' => '123',
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
        .with(text: 'Feature flag foo has been removed!')

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

  describe '#attachment_fields_per_state' do
    it 'returns attachment fields grouped per state ' do
      command = described_class
        .new([], { match: 'foo' }, 'GITLAB_TOKEN' => '123')

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
          'GITLAB_TOKEN' => '456'
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
          'GITLAB_TOKEN' => 'foo'
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

        command.log_feature_toggle('foo', 'bar')
      end

      it 'adds a label when incidents are ignored' do
        command = described_class.new(
          [],
          { ignore_incidents: true },
          'GITLAB_USER_LOGIN' => 'alice',
          'GITLAB_TOKEN' => 'foo'
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
            labels: 'host::gitlab.com, change, Incidents ignored',
            description: an_instance_of(String)
          )
          .and_return(issue)

        expect(client).to receive(:close_issue).with(1, 2)

        command.log_feature_toggle('foo', 'bar')
      end
    end
  end

  describe '#ongoing_incidents?' do
    context 'when there are no incidents' do
      it 'returns false' do
        command = described_class.new([], {}, 'GITLAB_TOKEN' => 'foo')
        client = instance_double(Chatops::Gitlab::Client)

        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'foo', host: 'gitlab.com')
          .and_return(client)

        expect(client)
          .to receive(:issues)
          .with(
            described_class::INCIDENTS_PROJECT,
            labels: 'incident',
            state: 'opened'
          )
          .and_return(Gitlab::PaginatedResponse.new([]))

        expect(command.ongoing_incidents?).to eq(false)
      end
    end

    context 'when there are incidents' do
      let(:command) { described_class.new([], {}, 'GITLAB_TOKEN' => 'foo') }
      let(:client) { instance_double(Chatops::Gitlab::Client) }

      before do
        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'foo', host: 'gitlab.com')
          .and_return(client)
      end

      it 'returns false when the --ignore-incidents option is specified' do
        command = described_class
          .new([], { ignore_incidents: true }, 'GITLAB_TOKEN' => 'foo')

        expect(client).not_to receive(:issues)

        expect(command.ongoing_incidents?).to eq(false)
      end

      it 'returns true when there is an S1 issue' do
        issue = instance_double('issue', labels: %w[S1 incident foo])

        expect(client)
          .to receive(:issues)
          .with(
            described_class::INCIDENTS_PROJECT,
            labels: 'incident',
            state: 'opened'
          )
          .and_return(Gitlab::PaginatedResponse.new([issue]))

        expect(command.ongoing_incidents?).to eq(true)
      end

      it 'returns true when there is an S2 issue' do
        issue = instance_double('issue', labels: %w[S2 incident foo])

        expect(client)
          .to receive(:issues)
          .with(
            described_class::INCIDENTS_PROJECT,
            labels: 'incident',
            state: 'opened'
          )
          .and_return(Gitlab::PaginatedResponse.new([issue]))

        expect(command.ongoing_incidents?).to eq(true)
      end

      it 'returns true when there is an S3 issue' do
        issue = instance_double('issue', labels: %w[S3 incident foo])

        expect(client)
          .to receive(:issues)
          .with(
            described_class::INCIDENTS_PROJECT,
            labels: 'incident',
            state: 'opened'
          )
          .and_return(Gitlab::PaginatedResponse.new([issue]))

        expect(command.ongoing_incidents?).to eq(true)
      end

      it 'returns false when there is an S3 issue' do
        issue = instance_double('issue', labels: %w[S4 incident foo])

        expect(client)
          .to receive(:issues)
          .with(
            described_class::INCIDENTS_PROJECT,
            labels: 'incident',
            state: 'opened'
          )
          .and_return(Gitlab::PaginatedResponse.new([issue]))

        expect(command.ongoing_incidents?).to eq(false)
      end
    end
  end
end
