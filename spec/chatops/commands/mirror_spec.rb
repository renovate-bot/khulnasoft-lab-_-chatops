# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Mirror do
  describe '.perform' do
    it 'includes examples in the --help output' do
      output = described_class.perform(%w[--help])

      expect(output).to include('Available subcommands:')
      expect(output).to include('Examples:')
    end
  end

  describe '#perform' do
    context 'when using a valid subcommand' do
      it 'executes the subcommand' do
        command = described_class.new(%w[status])

        expect(command)
          .to receive(:status)

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[not_a_real_command])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* status')
    end
  end

  describe '#status' do
    subject(:command) { described_class.new(%w[status], *env) }

    let(:slack_service) do
      instance_spy(
        'Chatops::Slack::MirrorMessage',
        general_status: 'foo',
        job_status: 'bar'
      )
    end

    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end

    let(:project) do
      {
        'path_with_namespace' => 'gitlab-org/security/gitlab',
        'forked_from_project' => {
          'avatar_url' => 'avatar.png',
          'name' => 'GitLab',
          'path_with_namespace' => 'gitlab-org/gitlab'
        }
      }
    end

    let(:mirror_status) do
      instance_double(
        'Chatops::Gitlab::SecurityMirrorStatus',
        available?: true,
        canonical: project['forked_from_project'],
        mirror_chain: 'Mirror chain',
        security_error: 'Security failed',
        build_error: 'Build failed',
        complete?: false
      )
    end

    # rubocop:disable RSpec/VerifiedDoubles
    let(:fake_client) { double('Chatops::Gitlab::Client').as_null_object }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)

      # rubocop:disable RSpec/SubjectStub
      allow(command)
        .to receive(:security_mirrors)
        .and_return([mirror_status])
      # rubocop:enable RSpec/SubjectStub

      allow(Chatops::Slack::MirrorMessage)
        .to receive(:new)
        .and_return(slack_service)
    end

    it 'reports the mirror status' do
      expect(slack_service)
        .to receive(:general_status)

      command.perform
    end

    context 'when running the security release pipeline' do
      let(:env) do
        [
          {},
          'SLACK_TOKEN' => 'token',
          'CHAT_CHANNEL' => 'channel',
          'GITLAB_TOKEN' => 'token',
          'SECURITY_RELEASE_PIPELINE' => 'true',
          'CI_JOB_URL' => 'https://example.com/foo/bar/-/jobs/1'
        ]
      end

      it 'reports the job status' do
        # rubocop:disable RSpec/SubjectStub
        allow(command).to receive(:synced_repositories?).and_return(true)
        # rubocop:enable RSpec/SubjectStub

        expect(slack_service).to receive(:job_status)

        command.perform
      end

      # rubocop:disable RSpec/NestedGroups
      context 'when the mirror check fails' do
        it 'raises an exception' do
          expect(slack_service).to receive(:job_status)

          expect { command.perform }
            .to raise_error(described_class::RepositoriesOutOfSync)
        end
      end
      # rubocop:enable RSpec/NestedGroups
    end
  end
end
