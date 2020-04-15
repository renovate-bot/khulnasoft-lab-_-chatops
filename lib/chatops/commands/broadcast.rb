# frozen_string_literal: true

module Chatops
  module Commands
    class Broadcast
      include Command

      usage "#{command_name} [MESSAGE] [OPTIONS]"
      description 'Managing of broadcast messages using the GitLab API.'

      # The supported time format for the --start and --end options.
      TIME_FORMAT = '%Y-%m-%d %H:%M'

      options do |o|
        o.string('--start', 'The start time of the message')
        o.string('--end', 'The end time of the message')
        o.string('--target-path', 'The target path of the message')

        o.separator <<~HELP.chomp

          Examples:

            Setting a broadcast message:

              broadcast --target-path * We will be deploying GitLab.com at 14:00 UTC

            You need to specify a --target-path to prevent accidental global broadcast messages.

            If a message contains quotes you must quote the entire message:

              broadcast "It's pretty cool don't you think?"

            By default a broadcast message starts at the current time and lasts
            an hour. To specify a custom start and/or end date/time you can
            use the --from and --until options:

              broadcast --target-path gitlab-org/* --start "2018-03-14 15:00" --end "2018-03-14 16:00" We are currently deploying GitLab.com.
        HELP
      end

      def perform
        message = arguments.join(' ')
        target_path = options[:target_path]

        return 'You must supply a message to set.' if message.empty?
        return 'You must specify a --target-path.' unless target_path

        Gitlab::Client
          .new(token: gitlab_token)
          .add_broadcast_message(
            message,
            target_path: target_path,
            starts_at: parse_time(:start),
            ends_at: parse_time(:end)
          )

        'The broadcast message has been added.'
      end

      # Parses a time string into an ISO 8601 formatted time string.
      #
      # option - The name of the option (:start or :end) containing the time
      #          string to parse.
      def parse_time(option)
        string = options[option]

        Time.strptime(string, TIME_FORMAT).iso8601 if string
      end
    end
  end
end
