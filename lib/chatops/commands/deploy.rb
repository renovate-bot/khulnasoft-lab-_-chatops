# frozen_string_literal: true

module Chatops
  module Commands
    # Command for triggering deploys using takeoff.
    class Deploy
      include Command

      usage "#{command_name} [VERSION] [ENVIRONMENT] [OPTIONS]"
      description 'Starts a deployment to a specified environment'

      SUBCOMMANDS = Set.new(%w[lock unlock]).freeze

      # Valid environments
      # NOTE: We deploy to `release`, but (un)lock a `release-gitlab` Chef role
      ENVIRONMENTS = %w[
        gprd gprd-cny
        gstg gstg-cny gstg-ref
        pre release release-gitlab
      ].freeze

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

      options do |o|
        o.bool('--warmup', 'Only perform a warmup, instead of a full deploy')
        o.bool('--check', 'Run with CHECKMODE (dry-run)')

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

        o.separator <<~HELP.chomp

          Available subcommands:

          #{available_subcommands}

          Examples:

            Lock the gprd environment, preventing new deploys

              lock gprd

            Unlock the gstg environment, allowing new deploys

              unlock gstg
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(SUBCOMMANDS.to_a.sort).to_s
      end

      def perform
        if SUBCOMMANDS.include?(arguments.first)
          command = arguments.shift

          public_send(command, *arguments)
        else
          version, target = arguments.shift(2)

          return 'Must provide a version and a target environment' if version.nil? || version.empty?

          # Handle a swapped environment/version argument
          version, target = target, version if ENVIRONMENTS.include?(version) && !ENVIRONMENTS.include?(target)

          deploy(version, target)
        end
      end

      def deploy(version, target)
        assert_environment!(target)
        prepared_version = prepare_version(version)

        unless version_valid?(prepared_version)
          return 'The specified version is invalid. ' \
            'Versions must be in the format MAJOR.MINOR.PATCH(-rcN)'
        end

        if target == 'release' && !prepared_version.match?(VERSION_REGEX)
          return 'The release environment is only allowed to receive ' \
            'packages soon to be released.  Auto-deploys and RC\'s are ' \
            'not allowed.'
        end

        if arguments.any?
          return "Unprocessed arguments detected: `#{arguments.inspect}`. " \
            'You may have forgotten quotes around the message for ' \
            '`--ignore-production-checks`?'
        end

        schedule_deploy(prepared_version, target)
      end

      # Lock an environment and prevent it from being deployed
      def lock(env)
        intent = 'lock'
        env = normalize_chef_environment(env)
        assert_environment!(env)

        error_message = "Invalid intent! #{env} is already in state #{intent}"

        return error_message unless valid_intent?(env, intent)

        Chef::Client.new.lock_environment(env)

        "#{env} has been locked, preventing new deploys"
      end

      # Unlock an environment and allow it to be deployed
      def unlock(env)
        intent = 'unlock'
        env = normalize_chef_environment(env)
        assert_environment!(env)
        valid_intent?(env, intent)

        error_message = "Invalid intent! #{env} is already in state #{intent}"

        return error_message unless valid_intent?(env, intent)

        Chef::Client.new.unlock_environment(env)

        "#{env} has been unlocked, allowing new deploys"
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

      def schedule_deploy(version, target)
        response = client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          environment_variables_for(version, target)
        )

        inc_rollbacks_metric(target) if options[:rollback]

        url = response.web_url
        "The deploy has been scheduled and can be viewed <#{url}|here>"
      rescue StandardError => error
        "The deploy could not be scheduled: #{error.message}"
      end

      def environment_variables_for(version, target)
        vars = {
          'DEPLOY_ENVIRONMENT': target,
          'DEPLOY_VERSION': version,
          'DEPLOY_REPO': repository,
          'DEPLOY_USER': env['GITLAB_USER_NAME'],
          'RELEASE_MANAGER': env['GITLAB_USER_LOGIN'],
          'IGNORE_PRODUCTION_CHECKS': sanitize_reason(
            options[:ignore_production_checks]
          )
        }

        vars[:TAKEOFF_WARMUP] = '1' if options[:warmup]
        vars[:ANSIBLE_SKIP_TAGS] = 'haproxy' if options[:skip_haproxy]
        vars[:CHECKMODE] = 'true' if options[:check]
        vars[:PRECHECK_IGNORE_ERRORS] = 'yes' if options[:allow_precheck_failure]

        if options[:rollback]
          vars[:DEPLOY_ROLLBACK] = 'true'
          vars[:IGNORE_PRODUCTION_CHECKS] = sanitize_reason('This is a rollback')
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

      def sanitize_reason(input)
        CGI.escape(input) if input
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

      # Returns the API token to use for interacting with delivery-metrics
      def delivery_metrics_token
        env.fetch('DELIVERY_METRICS_TOKEN')
      end

      # Returns the delivery-metrics endpoint
      def delivery_metrics_url
        env.fetch('DELIVERY_METRICS_URL')
      end

      def normalize_chef_environment(env)
        # Let's not be pedantic just because the Chef role is unusual
        if env == 'release'
          'release-gitlab'
        else
          env
        end
      end

      def assert_environment!(env)
        return if ENVIRONMENTS.include?(env)

        raise "Invalid environment `#{env}`, must be one of #{ENVIRONMENTS.join(', ')}"
      end

      ##
      # Validates that the state we intend is not already the case, if so return false
      #
      # This is to signal to the requester that something may be amiss
      def valid_intent?(env, intent)
        unlocked = Chef::Client.new.environment_unlocked?(env)

        intent == 'unlock' && !unlocked || intent == 'lock' && unlocked
      end

      def inc_rollbacks_metric(environment)
        HTTP
          .headers("X-Private-Token": delivery_metrics_token)
          .post(
            "#{delivery_metrics_url}/api/deployment_rollbacks_started_total/inc",
            form: { labels: environment }
          )
      end
    end
  end
end
