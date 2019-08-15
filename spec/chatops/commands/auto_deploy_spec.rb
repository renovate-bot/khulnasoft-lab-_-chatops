# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::AutoDeploy do
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

  describe '#status' do
    def expect_slack_message(block_matcher)
      message = instance_double('message')

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .and_return(message)

      expect(message)
        .to receive(:send)
        .with(blocks: block_matcher)
    end

    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end
    let(:production_status) do
      {
        host: 'gitlab.com',
        version: '12.2.0-pre',
        revision: '0874a8d346c',
        branch: '12-2-auto-deploy-20190804'
      }
    end

    # rubocop:disable RSpec/VerifiedDoubles
    let(:fake_client) { double('Gitlab::Client').as_null_object }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      stub_const('Gitlab::Client', fake_client)
    end

    context 'with no argument' do
      let(:command) do
        described_class.new(%w[status], *env)
      end

      it 'send a formatted Slack message' do
        allow(command).to receive(:environment_status)
          .and_return(production_status)
        expect_slack_message(StatusBlockMatcher.new(production_status))

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
          .and_return([{ name: production_status[:branch] }])

        fake_commit = instance_double(
          'Commit',
          short_id: 'abcd',
          title: 'Commit title'
        )
        expect(fake_client).to receive(:commit).and_return(fake_commit)

        expect_slack_message(
          DeployedCommitBlockMatcher.new(production_status, fake_commit)
        )

        command.perform
      end

      it 'posts an warning message with no deployed environment' do
        allow(command).to receive(:environment_status).and_return({})
        allow(command).to receive(:auto_deploy_branches).with('abcdefg')
          .and_return([])
        expect_slack_message(NoDeployedBlockMatcher.new)

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
      end

      it 'posts an error message' do
        expect_slack_message(InvalidCommitBlockMatcher.new('abcdefg'))

        command.perform
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
      json.include?(@status[:branch])
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
