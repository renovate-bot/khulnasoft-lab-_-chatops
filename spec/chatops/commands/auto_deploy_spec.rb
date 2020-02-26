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

  def expect_slack_message(args = {})
    message = instance_double('message')

    expect(Chatops::Slack::Message)
      .to receive(:new)
      .and_return(message)

    expect(message)
      .to receive(:send)
      .with(**args)
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

      expect(instance).to receive(:trigger_release)
        .with(nil, 'auto_deploy:tag', {})

      instance.perform
    end

    it 'supports a `--security` flag' do
      instance = stubbed_instance('tag', security: true)

      expect(instance).to receive(:trigger_release)
        .with(nil, 'auto_deploy:tag', hash_including(SECURITY: true))

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
        allow(command).to receive(:environment_status)
          .and_return(production_status)
        expect_slack_message(blocks: StatusBlockMatcher.new(production_status))

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

      it 'returns nil for the first env' do
        expect(promotable_env_revision(0)).to be_nil
      end

      it 'returns the revision of the previous env' do
        expect(promotable_env_revision(1)).to eq(production_rev)
        expect(promotable_env_revision(2)).to eq(canary_rev)
      end

      it 'returns nil for index out of bounds' do
        expect(promotable_env_revision(100)).to be_nil
      end
    end

    describe '#md_revision_field' do
      let(:command) { subject }

      def md_revision_field(current, promotable_to)
        command.send(:md_revision_field, current, promotable_to)
      end

      it 'shows the commit link and a comparison link' do
        current_rev = '1234'
        promotable_env_rev = 'abcf'

        expect(command).to receive(:commit_link)
          .with(current_rev).and_return('commit_link')
        expect(command).to receive(:compare_link)
          .with(promotable_env_rev, current_rev)
          .and_return('compare_link')

        expect(md_revision_field(current_rev, promotable_env_rev))
          .to eq('*Revision:* commit_link - compare_link')
      end

      it 'shows only the commit link when comparing to nil' do
        current_rev = '1234'
        expect(command).to receive(:commit_link)
          .with(current_rev).and_return('commit_link')
        expect(command).not_to receive(:compare_link)

        expect(md_revision_field(current_rev, nil))
          .to eq('*Revision:* commit_link')
      end

      it 'shows only the commit link when revisions are the same' do
        current_rev = '1234'
        expect(command).to receive(:commit_link)
          .with(current_rev).and_return('commit_link')
        expect(command).not_to receive(:compare_link)

        expect(md_revision_field(current_rev, current_rev))
          .to eq('*Revision:* commit_link')
      end
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
      json.include?("<https://#{@status[:host]}/|#{@status[:host]}>") &&
      json.include?(@status[:version]) &&
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
