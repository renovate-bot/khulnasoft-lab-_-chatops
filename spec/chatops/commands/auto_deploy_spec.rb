# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::AutoDeploy do
  let(:fake_client) { spy }

  let(:env) do
    [
      {},
      'SLACK_TOKEN' => 'token',
      'CHAT_CHANNEL' => 'channel',
      'GITLAB_TOKEN' => 'token',
      'GITLAB_OPS_TOKEN' => 'token',
      'CHEF_USERNAME' => 'bork',
      'CHEF_PEM_KEY' => 'bork'
    ]
  end

  before do
    stub_const('Chatops::Gitlab::Client', fake_client)
  end

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
        command = described_class.new(%w[status c01bc1930])

        expect(command)
          .to receive(:status)
          .with('c01bc1930')

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

  describe '#pause' do
    let(:command) { described_class.new(%w[pause], *env) }

    it 'triggers a pause' do
      auto_deploy = instance_double('Chatops::Gitlab::AutoDeploy')
      expect(Chatops::Gitlab::AutoDeploy).to receive(:new)
        .with(fake_client)
        .and_return(auto_deploy)

      tasks = [
        instance_double('task', active: false, description: 'foo'),
        instance_double('task', active: false, description: 'bar')
      ]
      expect(auto_deploy).to receive(:pause).and_return(tasks)
      expect(command).to receive(:post_task_status)
        .with(tasks)
        .and_call_original

      expect_slack_message(blocks: TaskBlockMatcher.new(tasks))
      command.perform
    end
  end

  describe '#prepare', :release_command do
    it 'triggers `auto_deploy:prepare`' do
      instance = stubbed_instance('prepare')

      expect(instance).to receive(:trigger_release)
        .with(nil, 'auto_deploy:prepare')

      instance.perform
    end
  end

  describe '#tag', :release_command do
    it 'triggers `auto_deploy:tag' do
      instance = stubbed_instance('tag')

      expect(instance).to receive(:trigger_release).with(nil, 'auto_deploy:tag')

      instance.perform
    end
  end

  describe '#unpause' do
    let(:command) { described_class.new(%w[unpause], *env) }

    it 'triggers an unpause' do
      auto_deploy = instance_double('Chatops::Gitlab::AutoDeploy')
      expect(Chatops::Gitlab::AutoDeploy).to receive(:new)
        .with(fake_client)
        .and_return(auto_deploy)

      tasks = [
        instance_double(
          'task',
          active: true,
          description: 'foo',
          next_run_at: 'Tomorrow'
        ),
        instance_double(
          'task',
          active: true,
          description: 'bar',
          next_run_at: 'Next week'
        )
      ]
      expect(auto_deploy).to receive(:unpause).and_return(tasks)
      expect(command).to receive(:post_task_status)
        .with(tasks)
        .and_call_original

      expect_slack_message(blocks: TaskBlockMatcher.new(tasks))
      command.perform
    end
  end

  describe '#status' do
    let(:production_status) do
      {
        role: 'gprd',
        host: 'gitlab.com',
        version: '12.2.0-pre',
        revision: '0874a8d346c',
        branch: '12-2-auto-deploy-20190804',
        package: '12.2.201908042020+0874a8d346c.2ee9f1d280d'
      }
    end

    context 'with no argument' do
      let(:command) do
        described_class.new(%w[status], *env)
      end

      it 'send a formatted Slack message' do
        allow(command).to receive(:trigger_production_checks?).and_return(true)

        allow(command).to receive(:environment_status)
          .and_return(production_status)
        expect_slack_message(blocks: StatusBlockMatcher.new(production_status))
        expect(command).to receive(:run_trigger).with(CHECK_PRODUCTION: 'true')

        command.perform
      end
    end

    context 'with a valid commit SHA' do
      let(:command) do
        described_class.new(%w[status abcdefg], *env)
      end

      it 'posts a message with deployed environments' do
        allow(command).to receive(:environment_status)
          .and_return(production_status)
        allow(command).to receive(:auto_deploy_branches).with('abcdefg')
          .and_return([instance_double(
            'Branch', name: production_status[:branch]
          )])

        fake_commit = instance_double(
          'Commit',
          short_id: 'abcd',
          title: 'Commit title'
        )
        expect(fake_client).to receive(:commit).and_return(fake_commit)

        expect_slack_message(
          blocks: DeployedCommitBlockMatcher.new(production_status, fake_commit)
        )

        command.perform
      end

      it 'posts an warning message with no deployed environment' do
        allow(command).to receive(:environment_status).and_return({})
        allow(command).to receive(:auto_deploy_branches).with('abcdefg')
          .and_return([])
        expect_slack_message(blocks: NoDeployedBlockMatcher.new)

        command.perform
      end
    end

    context 'with an invalid commit SHA' do
      let(:command) do
        described_class.new(%w[status abcdefg], *env)
      end

      before do
        allow(fake_client).to receive(:commit)
          .and_raise(gitlab_error(:NotFound))

        allow(command).to receive(:chef_client).and_return(
          instance_double('Chatops::Chef::Client', package_version: 'foo')
        )
      end

      it 'posts an error message' do
        expect_slack_message(blocks: InvalidCommitBlockMatcher.new('abcdefg'))

        command.perform
      end
    end

    describe '#promotable_env_revision' do
      let(:production_rev) { 'abc1234' }
      let(:canary_rev)     { 'fff1235' }
      let(:staging_rev)    { 'ddd1236' }
      let(:envs) do
        [
          { revision: production_rev },
          { revision: canary_rev },
          { revision: staging_rev }
        ]
      end

      def promotable_env_revision(index)
        subject.send(:promotable_env_revision, envs, index)
      end

      it 'returns nil for the last env' do
        expect(promotable_env_revision(2)).to be_nil
      end

      it 'returns the revision of the next env' do
        expect(promotable_env_revision(0)).to match('abc1234...fff1235')
        expect(promotable_env_revision(1)).to match('fff1235...ddd1236')
      end

      it 'returns nil for index out of bounds' do
        expect(promotable_env_revision(100)).to be_nil
      end
    end
  end

  describe '#blockers' do
    let(:command) { described_class.new([], *env) }

    it 'triggers a release-tools production check' do
      allow(command).to receive(:trigger_production_checks?).and_return(true)

      expect(command).to receive(:run_trigger).with(CHECK_PRODUCTION: 'true')

      expect(command.blockers)
        .to eq('Production checks triggered, the results will appear shortly.')
    end
  end

  describe '#lock' do
    let(:auto_deploy) { instance_double('Chatops::Gitlab::AutoDeploy') }

    before do
      allow(Chatops::Gitlab::AutoDeploy)
        .to receive(:new)
        .with(fake_client)
        .and_return(auto_deploy)
    end

    context 'when no custom branch is given' do
      it 'locks deploys to the deployed auto-deploy branch' do
        command = described_class.new([], *env)

        allow(command)
          .to receive(:environment_status)
          .with('gprd')
          .and_return(branch: 'foo')

        expect(auto_deploy).to receive(:pause_prepare)

        expect(fake_client)
          .to receive(:update_variable)
          .with('gitlab-org/release/tools', 'AUTO_DEPLOY_BRANCH', 'foo')

        command.lock
      end
    end

    context 'when a custom branch is given' do
      it 'locks deploys to the given branch' do
        command = described_class.new([], *env)

        expect(auto_deploy).to receive(:pause_prepare)

        expect(fake_client)
          .to receive(:update_variable)
          .with('gitlab-org/release/tools', 'AUTO_DEPLOY_BRANCH', 'foo')

        expect(command.lock('foo'))
          .to eq('Auto deploys have been locked to branch foo')
      end
    end
  end

  describe '#unlock' do
    it 'resumes the preparing of auto-deploy branches' do
      command = described_class.new([], *env)
      auto_deploy = instance_double('Chatops::Gitlab::AutoDeploy')

      allow(Chatops::Gitlab::AutoDeploy)
        .to receive(:new)
        .with(fake_client)
        .and_return(auto_deploy)

      expect(auto_deploy).to receive(:unpause_prepare)

      command.unlock
    end
  end
end

# RSpec argument matcher for verifying the complex `block` Hash passed to
# `Slack::Message#send` from the described class
class StatusBlockMatcher
  def initialize(status)
    @status = status
  end

  def ===(other)
    json = other.to_json

    json.include?(':party-tanuki:') &&
      json.include?(@status[:host]) &&
      json.include?(@status[:revision]) &&
      json.include?(@status[:branch]) &&
      json.include?(@status[:package])
  end
end

class DeployedCommitBlockMatcher
  def initialize(status, commit)
    @status = status
    @commit = commit
  end

  def ===(other)
    json = other.to_json

    json.include?("`#{@commit.short_id}`") &&
      json.include?(@commit.title) &&
      json.include?(@status[:host])
  end
end

class NoDeployedBlockMatcher
  def ===(other)
    other.to_json.include?(':warning: Unable to find a deployed branch')
  end
end

class InvalidCommitBlockMatcher
  def initialize(commit_sha)
    @commit_sha = commit_sha
  end

  def ===(other)
    other.to_json.include?(":exclamation: `#{@commit_sha}` not found")
  end
end

class TaskBlockMatcher
  def initialize(tasks)
    @tasks = tasks
  end

  def ===(other)
    json = other.to_json

    @tasks.all? do |task|
      icon = task.active ? ':white_check_mark:' : ':double_vertical_bar:'
      json.include?(icon) &&
        json.include?(task.description) &&
        json.include?(summary)
    end
  end

  private

  def summary
    if @tasks.all?(&:active)
      'Scheduled auto-deploy tasks have been re-enabled.'
    else
      'Scheduled auto-deploy tasks have been temporarily disabled.'
    end
  end
end
