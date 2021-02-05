# frozen_string_literal: true

module Chatops
  module Commands
    # Directly map ChatOps to the release-tools `release` task namespace
    class Release
      include Command
      include ::Chatops::Release::Command

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Perform release-related tasks.'

      COMMANDS = Set.new(
        %w[
          issue
          merge
          prepare
          qa
          status
          sync_remotes
          tag
          close_issues
          tracking_issue
        ]
      )

      # rubocop: disable Metrics/BlockLength
      options do |o|
        o.bool '--security',
               'Act as a security release',
               default: false

        o.bool '--critical',
               'Act as a critical security release',
               default: false

        o.bool '--default-branch',
               'Merge MRs targeting the default branch',
               default: false

        o.bool '--master',
               'DEPRECATED: Use `--default-branch`',
               default: false

        o.bool '--dry-run',
               'Operate in dry-run mode, which will avoid making changes',
               default: false

        o.string '--gitaly-sha',
                 'The SHA to use for creating the Gitaly stable branch'

        o.string '--gitlab-sha',
                 'The SHA to use for creating the GitLab stable branch'

        o.string '--omnibus-sha',
                 'The SHA to use for creating the Omnibus stable branch'

        o.string '--cng-sha',
                 'The SHA to use for creating the CNG stable branch'

        o.string '--helm-sha',
                 'The SHA to use for creating the Helm stable branch'

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

            Tag 1.2.3 but use a different SHA for the Gitaly stable branch:

              release tag --gitaly-sha 123abc 1.2.3

            Sync default and auto-deploy branches after a security release

              release sync_remotes --security

            Close security implementation issues associated with the Security Release Tracking Issue

              release close_issues --security

            Create a Security Release Tracking Issue

              release tracking_issue --security
        HELP
      end
      # rubocop: enable Metrics/BlockLength

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
          merge_default_branch =
            # Temporarily support either `--master` or `--default-branch`
            #
            # See https://gitlab.com/gitlab-com/gl-infra/delivery/-/issues/1440
            if options[:master] || options[:default_branch]
              '1'
            else
              ''
            end

          trigger_release(
            version,
            "#{namespace}:#{__method__}",
            'MERGE_MASTER_SECURITY_MERGE_REQUESTS' => merge_default_branch
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

      def status(version = nil)
        validate_version!(version) unless options[:security]

        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def tag(version)
        validate_version!(version)

        trigger_release(version, "#{namespace}:#{__method__}", tag_params)
      end

      def sync_remotes(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def close_issues(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      def tracking_issue(version = nil)
        trigger_release(version, "#{namespace}:#{__method__}")
      end

      private

      TAG_REGEX = /\Av\d+\.\d+\.\d+(-rc\d+)?\z/

      def tag_params
        params = {}
        shas = []

        %w[gitaly gitlab omnibus cng helm].each do |key|
          if (value = options[:"#{key}_sha"])
            shas << "#{key}=#{value}"
          end
        end

        params[:STABLE_BRANCH_SOURCE_COMMITS] = shas.join(',') if shas.any?
        params
      end

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
