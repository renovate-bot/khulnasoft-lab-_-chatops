# frozen_string_literal: true

module Chatops
  module Commands
    # Directly map ChatOps to the release-tools `release` task namespace
    class Release
      include Command
      include ::Chatops::Release::Command

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform release-related tasks.'

      COMMANDS = Set.new(%w[issue merge prepare qa tag])

      options do |o|
        o.bool '--security',
               'Act as a security release',
               default: false

        o.bool '--master',
               'Merge MRs targeting the master branch',
               default: false

        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Create a task issue for 1.2.3

              release issue 1.2.3

            Cherry-pick into preparation branches for 1.2.3-rc1

              release merge 1.2.3-rc1

            Merge security MRs

              release merge --security

            Prepare for 1.2.0

              release prepare 1.2.0

            Prepare for a security release

              release prepare --security

            Create a QA issue for changes between 1.2.0-rc1 and 1.2.0-rc3

              release qa 1.2.0-rc1 1.2.0-rc3

            Tag 1.2.3 as a security release

              release tag --security 1.2.3
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

          For more information run `release --help`.
        HELP
      end

      def issue(version)
        validate_version!(version)

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def merge(version = nil)
        if options[:security]
          merge_master = options[:master] ? '1' : ''

          trigger_release(
            version,
            "#{namespace}:#{__method__}",
            'MERGE_MASTER_SECURITY_MERGE_REQUESTS' => merge_master
          )
        else
          validate_version!(version)

          trigger_release(version, "#{namespace}:#{__method__}")
        end
      end

      def prepare(version = nil)
        validate_version!(version) unless options[:security]

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def qa(*tags)
        tags.flatten!
        tags = tags.first.split('..') if tags.size == 1

        validate_comparison!(tags)

        trigger_release(tags.join(','), "#{namespace}:#{__method__}")
      end

      def tag(version)
        validate_version!(version)

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      private

      TAG_REGEX = /\Av\d+\.\d+\.\d+(-rc\d+)?\z/

      def namespace
        if options[:security]
          'security'
        else
          'release'
        end
      end

      def validate_comparison!(tags)
        if tags.size != 2
          raise ArgumentError,
                "Invalid comparison provided: #{tags.join('..')}"
        end

        tags.each do |tag|
          unless TAG_REGEX.match?(tag)
            raise ArgumentError, "Invalid tag provided: #{tag}"
          end
        end
      end
    end
  end
end
