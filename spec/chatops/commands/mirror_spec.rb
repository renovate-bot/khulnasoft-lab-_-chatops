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
        build_error: 'Build failed'
      )
    end

    # rubocop:disable RSpec/VerifiedDoubles
    let(:fake_client) { double('Chatops::Gitlab::Client').as_null_object }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    it 'sends a formatted Slack message' do
      command = described_class.new(%w[status], *env)
      allow(command).to receive(:security_mirrors).and_return([mirror_status])

      expect_slack_message(MirrorStatusBlockMatcher.new(mirror_status))

      command.perform
    end
  end
end

# RSpec argument matcher for verifying the complex `block` Hash passed to
# `Slack::Message#send` from the described class
class MirrorStatusBlockMatcher
  def initialize(status)
    @status = status
  end

  def ===(other)
    project = @status.canonical
    json = other.to_json

    includes_security_error?(other) && includes_build_error?(other) &&
      json.include?(@status.mirror_chain) &&
      json.include?(project['avatar_url']) &&
      json.include?(project['name'])
  end

  private

  def includes_security_error?(other)
    other.one? do |block|
      block[:type] == 'section' &&
        block[:text][:text] == "```#{@status.security_error}```"
    end
  end

  def includes_build_error?(other)
    other.one? do |block|
      block[:type] == 'section' &&
        block[:text][:text] == "```#{@status.build_error}```"
    end
  end
end
