# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Slack::MirrorMessage do
  subject(:mirror_message) do
    described_class.new(security_mirrors: [mirror_status], env: environment_variables)
  end

  let(:environment_variables) do
    {
      'SLACK_TOKEN' => 'token',
      'CHAT_CHANNEL' => 'channel',
      'GITLAB_TOKEN' => 'token',
      'CI_JOB_URL' => 'https://example.com/foo/bar/-/jobs/1'
    }
  end

  let(:forked_from_project) do
    {
      'avatar_url' => 'avatar.png',
      'name' => 'GitLab',
      'path_with_namespace' => 'gitlab-org/gitlab'
    }
  end

  let(:mirror_status) do
    instance_double(
      'Chatops::Gitlab::SecurityMirrorStatus',
      available?: true,
      canonical: forked_from_project,
      mirror_chain: 'Mirror chain',
      security_error: 'Security failed',
      build_error: 'Build failed'
    )
  end

  describe '#general_status' do
    it 'posts an slack message' do
      expect_slack_message(blocks: MirrorStatusBlockMatcher.new(mirror_status))

      mirror_message.general_status
    end
  end

  describe '#job_status' do
    let(:job_message) do
      ':security-tanuki: :ci_passing: *Mirror check <https://example.com/foo/bar/-/jobs/1|successfully> executed*'
    end

    let(:block_message) do
      [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: job_message
          }
        }
      ]
    end

    it 'posts an slack message' do
      expect_slack_message(blocks: block_message)

      mirror_message.job_status
    end

    context 'when repositories are not synced' do
      let(:job_message) do
        ':security-tanuki: :ci_failing: *Some projects are out of sync, review the Slack output or the <https://example.com/foo/bar/-/jobs/1|job log> for details*'
      end

      it 'posts an slack message' do
        expect_slack_message(blocks: block_message)

        mirror_message.job_status(synced_repositories: false)
      end
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
        block[:text][:text] == "*Security*:\n```#{@status.security_error}```"
    end
  end

  def includes_build_error?(other)
    other.one? do |block|
      block[:type] == 'section' &&
        block[:text][:text] == "*Build*:\n```#{@status.build_error}```"
    end
  end
end
