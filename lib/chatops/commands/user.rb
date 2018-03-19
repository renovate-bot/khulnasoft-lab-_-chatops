# frozen_string_literal: true

module Chatops
  module Commands
    class User
      include Command

      usage "#{command_name} [SUBCOMMAND] [OPTIONS]"
      description 'Managing of users using the GitLab API.'

      # The color to use for active users.
      COLOR_ACTIVE = '#B3ED8E'

      # The color to use for blocked users.
      COLOR_BLOCKED = '#F55B5B'

      # All the available subcommands.
      COMMANDS = Set.new(%w[find block unblock])

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Obtaining details about a single user:

              user find alice

            Blocking a user:

              user block alice

            Unblocking a user:

              user unblock alice
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

      # Displays details of a single user.
      #
      # name - The username of the user.
      def find(name = nil)
        return 'You must specify a username.' unless name

        user = Gitlab::Client
          .new(token: gitlab_token)
          .find_user(name)

        if user
          submit_user_details(user)
        else
          user_not_found_error(name)
        end
      end

      # Blocks a single user.
      #
      # name - The username of the user to block.
      def block(name = nil)
        return 'You must specify a username to block.' unless name

        client = Gitlab::Client.new(token: gitlab_token)
        user = client.find_user(name)

        return user_not_found_error(name) unless user

        if client.block_user(user.id)
          'The user has been blocked.'
        else
          'The user could not be blocked.'
        end
      end

      # Unblocks a single user.
      #
      # name - The username of the user to unblock.
      def unblock(name = nil)
        return 'You must specify a username to unblock.' unless name

        client = Gitlab::Client.new(token: gitlab_token)
        user = client.find_user(name)

        return user_not_found_error(name) unless user

        if client.unblock_user(user.id)
          'The user has been unblocked.'
        else
          'The user could not be unblocked.'
        end
      end

      # rubocop: disable Method/MethodLength
      def submit_user_details(user)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
            attachments: [
              {
                author_icon: user.avatar_url,
                author_name: user.name,
                author_link: user.web_url,
                text: user.bio,
                color: color_for_user(user),
                fields: [
                  {
                    title: 'ID',
                    value: user.id,
                    short: true
                  },
                  {
                    title: 'Name',
                    value: user.name,
                    short: true
                  },
                  {
                    title: 'Email',
                    value: user.email,
                    short: true
                  },
                  {
                    title: 'State',
                    value: user.state,
                    short: true
                  },
                  {
                    title: '2FA',
                    value: two_factor_label_for_user(user),
                    short: true
                  },
                  {
                    title: 'Created At',
                    value: user.created_at,
                    short: true
                  },
                  {
                    title: 'Last Active At',
                    value: user.last_activity_on,
                    short: true
                  },
                  {
                    title: 'Last Login',
                    value: user.current_sign_in_at,
                    short: true
                  },
                  {
                    title: 'Projects Limit',
                    value: user.projects_limit,
                    short: true
                  },
                  {
                    title: 'Shared Runners Limit',
                    value: user.shared_runners_minutes_limit,
                    short: true
                  }
                ]
              }
            ]
          )
      end
      # rubocop: enable Method/MethodLength

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `user --help`.
        HELP
      end

      def two_factor_label_for_user(user)
        if user.two_factor_enabled
          ':status_success: Enabled'
        else
          ':status_warning: Disabled'
        end
      end

      def color_for_user(user)
        if user.state == 'blocked'
          COLOR_BLOCKED
        else
          COLOR_ACTIVE
        end
      end

      def gitlab_token
        env.fetch('GITLAB_TOKEN')
      end

      def slack_token
        env.fetch('SLACK_TOKEN')
      end

      def channel
        env.fetch('CHAT_CHANNEL')
      end

      def user_not_found_error(name)
        "No user could be found for the username #{name.inspect}."
      end
    end
  end
end
