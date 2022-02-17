# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Release, :release_command do
  describe '.perform' do
    it 'includes examples in the --help output' do
      output = described_class.perform(%w[--help])

      expect(output).to include('Available subcommands:')
      expect(output).to include('Examples:')
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* issue')
    end
  end

  describe '#perform' do
    include_context 'release command #perform'

    include_examples 'with a valid chatops job',    input: %w[issue 10.9.0]
    include_examples 'with an invalid chatops job', input: %w[issue 10.9.0]
    include_examples 'with a dry-run flag',         input: %w[issue 10.9.0]
    include_examples 'with a critical flag',        input: %w[issue 10.9.0]

    context 'when using a valid subcommand' do
      it 'executes the subcommand' do
        command = described_class.new(%w[issue 1.2.3])

        expect(command)
          .to receive(:issue)
          .with('1.2.3')

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[invalid])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe 'subcommands' do
    let(:version) { '10.9.0' }

    include_context 'release command #perform'

    describe '#issue' do
      it 'triggers a normal release' do
        instance = stubbed_instance('issue', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:issue')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('issue', version, security: true)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'security:issue')

        instance.perform
      end
    end

    describe '#merge' do
      it 'triggers a normal release' do
        instance = stubbed_instance('merge', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:merge')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('merge', nil, security: true, master: false)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release).with(
          nil,
          'security:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => '')
        )

        instance.perform
      end

      it 'triggers a security release with a `--master` flag' do
        instance = stubbed_instance('merge', nil, security: true, master: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release).with(
          nil,
          'security:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => '1')
        )

        instance.perform
      end

      it 'triggers a security release with a `--default-branch` flag' do
        instance = stubbed_instance(
          'merge',
          nil,
          security: true,
          default_branch: true
        )

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release).with(
          nil,
          'security:merge',
          a_hash_including('MERGE_MASTER_SECURITY_MERGE_REQUESTS' => '1')
        )

        instance.perform
      end
    end

    describe '#prepare' do
      it 'triggers a normal release' do
        instance = stubbed_instance('prepare', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:prepare')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('prepare', nil, security: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:prepare')

        instance.perform
      end
    end

    describe '#qa' do
      it 'triggers a normal release' do
        tags = %w[v1.2.3 v1.3.0-rc1]
        instance = stubbed_instance('qa', tags)

        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'release:qa')

        instance.perform
      end

      it 'triggers a security release' do
        tags = %w[v1.2.3 v1.3.0-rc1]
        instance = stubbed_instance('qa', tags, security: true)

        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'security:qa')

        instance.perform
      end

      it 'supports a single range argument' do
        tags = %w[v1.2.3 v1.3.0-rc1]
        instance = stubbed_instance('qa', tags.join('..'))

        expect(instance).to receive(:validate_comparison!).with(tags)
          .and_call_original
        expect(instance).to receive(:trigger_release)
          .with(tags.join(','), 'release:qa')

        instance.perform
      end
    end

    describe '#status' do
      it 'triggers status for a normal release' do
        instance = stubbed_instance('status', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:status')

        instance.perform
      end

      it 'triggers status for a security release' do
        instance = stubbed_instance('status', nil, security: true)

        expect(instance).not_to receive(:validate_version!)
        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:status')

        instance.perform
      end
    end

    describe '#build_status' do
      it 'returns a default message when no versions are given' do
        instance = stubbed_instance('build_status')

        expect(instance.perform)
          .to eq('You must specify at least a single version')
      end

      # rubocop: disable RSpec/ExampleLength
      it 'sends a message containing the build status for a given version' do
        instance = stubbed_instance('build_status', '1.0.0')
        ce_pipeline = instance_double(
          'ce pipeline',
          web_url: 'http://example.com'
        )

        allow(instance).to receive(:slack_token).and_return('123')
        allow(instance).to receive(:channel).and_return('foo')
        allow(instance).to receive(:dev_token).and_return('bar')

        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: 'bar', host: 'dev.gitlab.org')
          .and_return(stubbed_client)

        allow(stubbed_client)
          .to receive(:pipelines)
          .with('gitlab/omnibus-gitlab', ref: '1.0.0+ce.0')
          .and_return([ce_pipeline])

        allow(stubbed_client)
          .to receive(:pipelines)
          .with('gitlab/omnibus-gitlab', ref: '1.0.0+ee.0')
          .and_return([])

        allow(instance)
          .to receive(:pipeline_status_per_stage)
          .with(stubbed_client, ce_pipeline)
          .and_return(
            'package-and-image' => 'success',
            'package-and-image-release' => 'running'
          )

        blocks = [
          {
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: "<http://example.com|*1.0.0+ce.0*>\n:status_success: packaging :status_running: publishing"
            }
          },
          {
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: "*1.0.0+ee.0*\nNo pipeline has been created yet"
            }
          }
        ]

        expect_slack_message(blocks: blocks)

        expect(instance.perform).to eq('')
      end
      # rubocop: enable RSpec/ExampleLength
    end

    describe '#tag' do
      it 'triggers a normal release' do
        instance = stubbed_instance('tag', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:tag', {})

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('tag', version, security: true)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'security:tag', {})

        instance.perform
      end

      it 'supports overriding the SHAs to use for stable branches' do
        instance = stubbed_instance(
          'tag',
          version,
          'gitaly_sha': '123abc',
          'gitlab_sha': '456def'
        )

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release).with(
          version,
          'release:tag',
          STABLE_BRANCH_SOURCE_COMMITS: 'gitaly=123abc,gitlab=456def'
        )

        instance.perform
      end
    end

    describe '#sync_remotes' do
      it 'triggers sync_remotes in a security release' do
        instance = stubbed_instance('sync_remotes', nil, security: true)

        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:sync_remotes')

        instance.perform
      end
    end

    describe '#close_issues' do
      it 'triggers close_issues in a security release' do
        instance = stubbed_instance('close_issues', nil, security: true)

        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:close_issues')

        instance.perform
      end
    end

    describe '#tracking_issue' do
      it 'triggers tracking_issue in a security release' do
        instance = stubbed_instance('tracking_issue', nil, security: true)

        expect(instance).to receive(:trigger_release)
          .with(nil, 'security:tracking_issue')

        instance.perform
      end
    end

    describe '#check' do
      it 'checks if MR URL is provided' do
        instance = stubbed_instance('check', nil, '14.2')

        expect(Chatops::Gitlab::ReleaseCheck::Service).not_to receive(:new)

        message =
          'You must specify a merge request URL and an optional self-managed release version. ' \
          'Ex: `release check https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345` or ' \
          '`release check https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345 14.2`'

        expect(instance.perform).to eq(message)
      end

      it 'allows nil version' do
        env = { 'GITLAB_TOKEN' => 'token' }
        instance = stubbed_instance('check', 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345', nil, env: env)
        service = instance_spy(Chatops::Gitlab::ReleaseCheck::Service)

        allow(Chatops::Gitlab::ReleaseCheck::Service)
          .to receive(:new)
          .with('https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345', nil, 'token')
          .and_return(service)

        instance.perform

        expect(service).to have_received(:execute)
      end

      it 'calls ReleaseCheck::Service' do
        env = { 'GITLAB_TOKEN' => 'token' }
        instance = stubbed_instance('check', 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345', '14.1', env: env)
        service = instance_spy(Chatops::Gitlab::ReleaseCheck::Service)

        allow(Chatops::Gitlab::ReleaseCheck::Service)
          .to receive(:new)
          .with('https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345', '14.1', 'token')
          .and_return(service)

        instance.perform

        expect(service).to have_received(:execute)
      end
    end
  end

  describe '#pipeline_status_per_stage' do
    # rubocop: disable RSpec/ExampleLength
    it 'returns the status per stage' do
      instance = stubbed_instance
      gitlab = instance_spy(Chatops::Gitlab::Client)
      pipeline = instance_double('pipeline', project_id: 1, id: 2)
      job1 = instance_double(
        'job1',
        stage: 'foo',
        status: 'running',
        allow_failure: false
      )

      job2 = instance_double(
        'job2',
        stage: 'foo',
        status: 'failed',
        allow_failure: false
      )

      job3 = instance_double(
        'job3',
        stage: 'bar',
        status: 'pending',
        allow_failure: false
      )

      job4 = instance_double(
        'job3',
        stage: 'baz',
        status: 'failed',
        allow_failure: true
      )

      allow(gitlab)
        .to receive(:pipeline_jobs)
        .with(1, 2)
        .and_return(Gitlab::PaginatedResponse.new([job1, job2, job3, job4]))

      expect(instance.send(:pipeline_status_per_stage, gitlab, pipeline))
        .to eq('foo' => 'failed', 'bar' => 'pending', 'baz' => 'success')
    end
    # rubocop: enable RSpec/ExampleLength
  end
end
