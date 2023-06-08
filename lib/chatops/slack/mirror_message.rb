# frozen_string_literal: true

module Chatops
  module Slack
    class MirrorMessage
      def initialize(security_mirrors:, env:)
        @security_mirrors = security_mirrors
        @env = env
      end

      def general_status
        blocks = ::Slack::BlockKit.blocks

        security_mirrors.each do |mirror|
          mirror_block(mirror, blocks)
        end

        post_status(blocks)
      end

      def job_status(synced_repositories: true)
        blocks = ::Slack::BlockKit.blocks
        text = job_message(synced_repositories)

        blocks.section do |section|
          section.mrkdwn(text: text)
        end

        post_status(blocks)
      end

      private

      attr_reader :security_mirrors, :env

      def mirror_block(mirror, blocks)
        canonical = mirror.canonical

        blocks.context do |context|
          unless canonical['avatar_url'].nil?
            context
              .image(url: canonical['avatar_url'], alt_text: canonical['name'])
          end

          context
            .mrkdwn(text: "*#{canonical['name']}* -- #{mirror.mirror_chain}")
        end

        # rubocop:disable Style/GuardClause
        if mirror.security_error
          blocks.section do |s|
            s.mrkdwn(text: "*Security*:\n```#{mirror.security_error}```")
          end
        end

        if mirror.build_error
          blocks.section do |s|
            s.mrkdwn(text: "*Build*:\n```#{mirror.build_error}```")
          end
        end
        # rubocop:enable Style/GuardClause
      end

      def post_status(blocks)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(blocks: blocks.as_json)
      end

      def job_message(synced_repositories)
        [].tap do |text|
          text << ':security-tanuki:'
          text << (synced_repositories ? ':ci_passing:' : ':ci_failing:')
          text << job_text_message(synced_repositories)
        end.join(' ')
      end

      def job_text_message(synced_repositories)
        if synced_repositories
          "*Mirror check <#{job_url}|successfully> executed*"
        else
          "*Some projects are out of sync, review the Slack output or the <#{job_url}|job log> for details*"
        end
      end

      def slack_token
        env.fetch('SLACK_TOKEN')
      end

      def channel
        env.fetch('CHAT_CHANNEL')
      end

      def job_url
        env.fetch('CI_JOB_URL')
      end
    end
  end
end
