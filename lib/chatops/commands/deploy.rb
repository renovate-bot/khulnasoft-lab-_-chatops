# frozen_string_literal: true

module Chatops
  module Commands
    # Command for triggering deploys using takeoff.
    class Deploy
      include Command

      usage "#{command_name} [VERSION] [OPTIONS]"
      description 'Schedules a deployment using takeoff'

      # The regular expression to use for verifying release candidate versions.
      RC_VERSION_REGEX = /\A\d+\.\d+\.\d+-rc\d+?\.ee\.\d+\z/

      # The regular expression to use for verifying regular release versions.
      VERSION_REGEX = /\A\d+\.\d+\.\d+-ee\.\d+\z/

      # The regular expression to use for verifying auto-deploy versions
      #   The auto-deploy version may change due to
      #   https://gitlab.com/gitlab-org/release/framework/issues/343
      #   this regex allows for both options
      AUTO_DEPLOY_REGEX = /\A\d+\.\d+\.\d+[+-][^ ]{7,}\.[^ ]{7,}\z/

      # Default package repository to use if TAKEOFF_DEPLOY_REPO is undefined
      DEFAULT_REPO = 'gitlab/pre-release'

      options do |o| # rubocop:disable Metrics/BlockLength
        o.bool('--production', 'Deploy to production, instead of staging')

        o.bool(
          '--canary',
          'Only deploy to a canary, instead of the entire environment'
        )

        o.bool(
          '--pre',
          'Deploy to the PreProd environment'
        )

        o.bool('--release', 'Deploy to the Release environment')

        o.bool('--warmup', 'Only perform a warmup, instead of a full deploy')

        o.bool(
          '--allow-precheck-failure',
          'Allow the version and alert prechecks to fail'
        )

        o.bool(
          '--skip-haproxy',
          'Skip the ansible haproxy tasks'
        )

        o.bool(
          '--rollback',
          'Initiate a rollback deploy'
        )

        o.string(
          '--ignore-production-checks',
          'Reason for bypassing production checks',
          default: 'false'
        )
      end

      def perform
        version = arguments[0]

        unless version?
          return 'The first argument must be the version to deploy'
        end

        version = prepare_version(version)

        unless version_valid?(version)
          return 'The specified version is invalid. ' \
            'Versions must be in the format MAJOR.MINOR.PATCH(-rcN)'
        end

        if environment == 'release' && !version.match?(VERSION_REGEX)
          return 'The release environment is only allowed to receive ' \
            'packages soon to be released.  Auto-deploys and RC\'s are ' \
            'not allowed.'
        end

        schedule_deploy(version)
      end

      def prepare_version(version)
        # If it's an auto-deploy version no changes are necessary
        return version if version.match?(AUTO_DEPLOY_REGEX)

        # In most cases the package we want to deploy will end in .ee.0
        # (e.g. 11.0.ee.0). To make deploying easier, we will add this suffix
        # automatically if not already present.
        is_rc = version.include?('-rc')

        # To make things eaiser, RCs use a slightly different version format
        # compared to regular versions
        search_for = is_rc ? '.ee.' : '-ee'
        suffix = is_rc ? '.ee.0' : '-ee.0'

        if version.include?(search_for)
          version
        else
          version + suffix
        end
      end

      def version_valid?(version)
        regex = if version.include?('-rc')
                  RC_VERSION_REGEX
                else
                  Regexp.union(VERSION_REGEX, AUTO_DEPLOY_REGEX)
                end

        version.match?(regex)
      end

      def schedule_deploy(version)
        response = client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          environment_variables_for(version)
        )

        url = response.web_url

        "The deploy has been scheduled and can be viewed <#{url}|here>"
      rescue StandardError => error
        "The deploy could not be scheduled: #{error.message}"
      end

      def environment_variables_for(version)
        vars = {
          'DEPLOY_ENVIRONMENT': environment,
          'DEPLOY_VERSION': version,
          'DEPLOY_REPO': repository,
          'DEPLOY_USER': env['GITLAB_USER_NAME'],
          'RELEASE_MANAGER': env['GITLAB_USER_LOGIN'],
          'IGNORE_PRODUCTION_CHECKS': options[:ignore_production_checks]
        }

        vars[:TAKEOFF_WARMUP] = '1' if options[:warmup]
        vars[:ANSIBLE_SKIP_TAGS] = 'haproxy' if options[:skip_haproxy]
        vars[:DEPLOY_ROLLBACK] = 'yes' if options[:rollback]
        if options[:allow_precheck_failure]
          vars[:PRECHECK_IGNORE_ERRORS] = 'yes'
        end

        vars
      end

      def client
        # For triggers we don't need an API token, so we explicitly set it to
        # nil.
        @client ||= Gitlab::Client.new(token: nil, host: trigger_host)
      end

      def repository
        env.fetch('TAKEOFF_DEPLOY_REPO', DEFAULT_REPO)
      end

      def trigger_token
        env.fetch('TAKEOFF_TRIGGER_TOKEN')
      end

      def trigger_project
        env.fetch('TAKEOFF_TRIGGER_PROJECT')
      end

      def trigger_host
        env.fetch('TAKEOFF_TRIGGER_HOST')
      end

      def environment
        base =
          if options[:production]
            'gprd'
          elsif options[:pre]
            'pre'
          elsif options[:release]
            'release'
          else
            'gstg'
          end

        if options[:canary]
          "#{base}-cny"
        else
          base
        end
      end

      def version
        arguments[0]
      end

      def version?
        if version && !version.empty?
          true
        else
          false
        end
      end
    end
  end
end
