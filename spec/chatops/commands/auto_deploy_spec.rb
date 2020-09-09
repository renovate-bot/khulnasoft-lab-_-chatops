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
        allow(command).to receive(:trigger_production_checks?).and_return(true)

        allow(command).to receive(:environment_status)
          .and_return(production_status)
        expect_slack_message(blocks: StatusBlockMatcher.new(production_status))
        expect(command).to receive(:run_trigger).with(CHECK_PRODUCTION: 'true')

        command.perform
      end

      # rubocop:disable RSpec/NestedGroups
      context 'when TRIGGER_PRODUCTION_CHECKS not set' do
        it 'will not trigger a production check' do
          allow(command).to receive(:trigger_production_checks?)
            .and_return(false)

          allow(command).to receive(:environment_status)
            .and_return(production_status)
          expect_slack_message(
            blocks: StatusBlockMatcher.new(production_status)
          )
          expect(command).not_to receive(:run_trigger)

          command.perform
        end
      end
      # rubocop:enable RSpec/NestedGroups
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

  describe '#blockers' do
    let(:command) { described_class.new([], *env) }

    it 'triggers a release-tools production check' do
      allow(command).to receive(:trigger_production_checks?).and_return(true)

      expect(command).to receive(:run_trigger).with(CHECK_PRODUCTION: 'true')

      command.blockers
    end

    context 'when TRIGGER_PRODUCTION_CHECKS not set' do
      # rubocop:disable Metrics/LineLength
      # rubocop:disable RSpec/NestedGroups

      let(:blocks) { instance_spy(Slack::BlockKit::Blocks) }
      let(:section) { instance_spy(Slack::BlockKit::Layout::Section) }
      let(:context) { instance_spy(Slack::BlockKit::Layout::Context) }

      before do
        allow(command).to receive(:trigger_production_checks?).and_return(false)

        allow(Slack::BlockKit).to receive(:blocks).and_return(blocks)
        allow(blocks).to receive(:section).and_yield(section)
        allow(blocks).to receive(:context).and_return(context)
      end

      context 'when there are no open issues' do
        it 'submits a message saying there are no issues' do
          allow(command).to receive(:production_issues).and_return([])

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('no ongoing incidents'))

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('no ongoing changes'))

          expect(command.send(:slack_message)).to receive(:send)
          expect(command).not_to receive(:run_trigger)

          command.blockers
        end
      end

      context 'when there is one incident and one change issue' do
        it 'submits a message including details about the issues' do
          incident = instance_double(
            'issue',
            web_url: 'foo',
            title: 'Foo',
            labels: %w[severity::1]
          )

          change =
            instance_double('issue', web_url: 'foo', title: 'Foo', labels: %w[C1])

          allow(command)
            .to receive(:production_issues)
            .with(described_class::INCIDENT_ISSUE_LABEL_PAIRS)
            .and_return([incident])

          allow(command)
            .to receive(:production_issues)
            .with(described_class::CHANGE_ISSUE_LABEL_PAIRS)
            .and_return([change])

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('1 ongoing incident'))

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('1 ongoing change'))

          expect(command.send(:slack_message)).to receive(:send)

          command.blockers
        end
      end

      context 'when there are multiple incidents and changes' do
        it 'submits a message including details about the issues' do
          incident = instance_double(
            'issue',
            web_url: 'foo',
            title: 'Foo',
            labels: %w[severiy::1]
          )

          change =
            instance_double('issue', web_url: 'foo', title: 'Foo', labels: %w[C1])

          allow(command)
            .to receive(:production_issues)
            .with(described_class::INCIDENT_ISSUE_LABEL_PAIRS)
            .and_return([incident, incident])

          allow(command)
            .to receive(:production_issues)
            .with(described_class::CHANGE_ISSUE_LABEL_PAIRS)
            .and_return([change, change])

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('2 ongoing incidents'))

          expect(section)
            .to receive(:mrkdwn)
            .with(text: a_string_including('2 ongoing changes'))

          expect(command.send(:slack_message)).to receive(:send)

          command.blockers
        end
      end
    end
    # rubocop:enable Metrics/LineLength
    # rubocop:enable RSpec/NestedGroups
  end

  describe '#production_issues' do
    it 'returns all production issues that have certain labels' do
      command = described_class.new([], *env)
      issue = instance_double('issue')

      allow(fake_client)
        .to receive(:issues)
        .with(described_class::PRODUCTION_PROJECT, labels: 'a', state: 'opened')
        .and_return(Gitlab::PaginatedResponse.new([issue]))

      expect(command.send(:production_issues, %w[a])).to eq([issue])
    end
  end

  describe '#issue_severity_indicator' do
    it 'returns the issue severity indicator when found' do
      issue = instance_double(
        'issue',
        web_url: 'foo',
        title: 'Foo',
        labels: %w[severity::1]
      )

      expect(described_class.new.send(:issue_severity_indicator, issue))
        .to eq(':red_circle:')
    end

    it 'returns a fallback indicator when no indicator could be found' do
      issue =
        instance_double('issue', web_url: 'foo', title: 'Foo', labels: [])

      expect(described_class.new.send(:issue_severity_indicator, issue))
        .to eq(':white_circle:')
    end
  end

  describe '#add_blocking_issue_contexts' do
    it 'adds a context for an issue' do
      blocks = instance_spy(Slack::BlockKit::Blocks)
      context = instance_spy(Slack::BlockKit::Layout::Context)
      issue = instance_double(
        'issue',
        web_url: 'foo',
        title: 'Foo',
        labels: %w[severity::1]
      )

      expect(blocks).to receive(:context).and_yield(context)
      expect(context).to receive(:mrkdwn).with(text: ':red_circle: <foo|Foo>')

      described_class.new.send(:add_blocking_issue_contexts, blocks, [issue])
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
