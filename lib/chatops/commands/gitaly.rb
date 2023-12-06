# frozen_string_literal: true

module Chatops
  module Commands
    class Gitaly
      include Command
      include ::Chatops::Release::Command

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform Gitaly release-related tasks.'

      COMMANDS = %w[tag].freeze

      options do |o|
        o.bool '--security',
               'Act as a security release',
               default: false

        o.separator <<~HELP.chomp

          Examples:

            Tag version 1.2.3

              gitaly tag 1.2.3

            Tag version 1.2.3 as a security release

              gitaly tag --security 1.2.3

        HELP
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command, *arguments[1..])
        else
          unsupported_command
        end
      end

      def tag(version)
        validate_version!(version)

        namespace_prefix = if options[:security]
                             'security'
                           else
                             'release'
                           end

        trigger_release(version, "#{namespace_prefix}:gitaly:tag")
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
