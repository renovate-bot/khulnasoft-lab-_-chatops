# frozen_string_literal: true

module Chatops
  module Commands
    class Mirror
      include Command

      COMMANDS = Set.new(%w[status])

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check the status of all Security mirrors:

              status
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.to_a.sort).to_s
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command, *arguments[1..-1])
        else
          unsupported_command
        end
      end

      def status
        blocks = ::Slack::BlockKit.blocks

        security_mirrors.each do |mirror|
          mirror_block(mirror, blocks)
        end

        post_status(blocks)
      end

      private

      def security_mirrors
        @security_mirrors ||= client
          .group_projects('gitlab-org/security', include_subgroups: true)
          .auto_paginate
          .map(&:to_h)
          .select { |p| p.key?('forked_from_project') }
          .sort_by { |p| p['path'] }
          .map { |p| Gitlab::SecurityMirrorStatus.new(p) }
          .select(&:available?)
      end

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

      def client
        @client ||= Gitlab::Client.new(token: gitlab_token)
      end
    end
  end
end
