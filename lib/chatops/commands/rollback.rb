# frozen_string_literal: true

module Chatops
  module Commands
    class Rollback
      include Command
      include ::Chatops::Release::Command

      COMMANDS = Set.new(%w[check]).freeze
      ENVIRONMENTS = %w[gprd gprd-cny gstg gstg-cny].freeze

      options do |o|
        o.string '--target', 'The target version that we want to rollback to'

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check if the latest staging deploy can be rolled back

              check gstg
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

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          The provided subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `rollback --help`.
        HELP
      end

      def check(env_name)
        unless ENVIRONMENTS.include?(env_name)
          return "Invalid environment `#{env_name}`, " \
            "expected `#{ENVIRONMENTS.join(', ')}`"
        end

        trigger_release(
          nil,
          'auto_deploy:rollback_check',
          ROLLBACK_TARGET: options[:target],
          ROLLBACK_ENV: env_name
        )
      end
    end
  end
end
