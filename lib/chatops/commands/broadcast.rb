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

        o.separator <<~HELP.chomp

          Examples:

            Setting a broadcast message:

              broadcast We will be deploying GitLab.com at 14:00 UTC

            If a message contains quotes you must quote the entire message:

              broadcast "It's pretty cool don't you think?"

            By default a broadcast message starts at the current time and lasts
            indefinitely. To specify a custom start and/or end date/time you can
            use the --from and --until options:

              broadcast --start "2018-03-14 15:00" --end "2018-03-14 16:00" We are currently deploying GitLab.com.
        HELP
      end

      def perform
        message = arguments.join(' ')

        if message.empty?
          'You must supply a message to set.'
        else
          Gitlab::Client
            .new(token: gitlab_token)
            .add_broadcast_message(
              message,
              starts_at: parse_time(:start),
              ends_at: parse_time(:end)
            )

          'The broadcast message has been added.'
        end
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
