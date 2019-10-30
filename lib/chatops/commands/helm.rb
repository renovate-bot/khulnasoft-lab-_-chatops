# frozen_string_literal: true

module Chatops
  module Commands
    class Helm
      include Command
      include ::Chatops::Release::Command

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform Helm Chart release-related tasks.'

      COMMANDS = %w[tag].freeze

      options do |o|
        o.separator <<~HELP.chomp

          Examples:

            Tag Charts version 2.1.1 using GitLab version 12.1.1

              helm tag 2.1.1 12.1.1
        HELP
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command, *arguments[1..-1])
        else
          unsupported_command
        end
      end

      def tag(charts_version, gitlab_version)
        validate_version!(charts_version)
        validate_version!(gitlab_version)

        trigger_release(gitlab_version,
                        'release:helm:tag',
                        'CHARTS_VERSION' => charts_version)
      end

      private

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `release --help`.
        HELP
      end
    end
  end
end
