# frozen_string_literal: true

module Chatops
  module Commands
    # Command for triggering deploys using takeoff.
    class Deploy
      include Command

      usage "#{command_name} [VERSION] [OPTIONS]"
      description 'Schedules a deployment using takeoff'

      # The regular expression to use for verifying package versions.
      #
      # Allowed formats:
      #
      # * 11.3.0.ee.0
      # * 11.3.0-rc1.ee.0
      VERSION_REGEX = /\A\d+\.\d+\.\d+(-rc\d+)?\.ee\.\d+\z/

      # Default package repository to use if TAKEOFF_DEPLOY_REPO is undefined
      DEFAULT_REPO = 'gitlab/pre-release'

      options do |o|
        o.bool('--production', 'Deploy to production, instead of staging')

        o.bool(
          '--canary',
          'Only deploy to a canary, instead of the entire environment'
        )

        o.bool('--warmup', 'Only perform a warmup, instead of a full deploy')
      end

      def perform
        version = arguments[0]

        unless version?
          return 'The first argument must be the version to deploy'
        end

        unless version.match?(VERSION_REGEX)
          return 'The specified version is invalid. ' \
            'Versions must be in the format MAJOR.MINOR.PATCH(-rcN)'
        end

        schedule_deploy(version)
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
          'DEPLOY_REPO': repository
        }

        vars[:TAKEOFF_WARMUP] = '1' if options[:warmup]

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
