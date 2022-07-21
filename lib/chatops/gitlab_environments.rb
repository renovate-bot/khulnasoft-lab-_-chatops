# frozen_string_literal: true

module Chatops
  module GitlabEnvironments
    DEV_HOST = 'dev.gitlab.org'
    STAGING_HOST = 'staging.gitlab.com'
    STAGING_REF_HOST = 'staging-ref.gitlab.com'
    OPS_HOST = 'ops.gitlab.net'
    PRE_HOST = 'pre.gitlab.com'
    PRODUCTION_HOST = 'gitlab.com'

    def self.included(mod)
      mod.extend(ClassMethods)
    end

    ICONS = {
      'gprd' => 'party-tanuki',
      'gprd-cny' => 'canary',
      'gstg' => 'building_construction',
      'gstg-cny' => 'hatching_chick',
      'gstg-ref' => 'construction',
      'pre' => 'pretzel',
      'db/gstg' => 'database',
      'db/gprd' => 'database'
    }.freeze

    def self.define_environment_options(options)
      options.boolean('--dev', "Use #{DEV_HOST}")
      options.boolean('--staging', "Use #{STAGING_HOST}")
      options.boolean('--staging-ref', "Use #{STAGING_REF_HOST}")
      options.boolean('--ops', "Use #{OPS_HOST}")
      options.boolean('--pre', "Use #{PRE_HOST}")
      options.boolean('--production', "Use #{PRODUCTION_HOST}")
    end

    def env_icon(environment)
      ICONS.fetch(environment, 'question')
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    def environments
      return @environments if defined?(@environments)

      Environment.initialize_all!(env)

      @environments = []
      @environments << Environment.dev if options[:dev]
      @environments << Environment.staging if options[:staging]
      @environments << Environment.staging_ref if options[:staging_ref]
      @environments << Environment.ops if options[:ops]
      @environments << Environment.pre if options[:pre]
      @environments << Environment.production if environments.empty? || options[:production]

      if @environments.count > 1 && !self.class.instance_variable_get('@multi_environments_enabled')
        raise 'this chatops command does not support multiple environments'
      end

      @environments
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize

    def environment
      raise "You expected a single environment but we've got multiple defined" unless environments.count == 1

      environments.first
    end

    module ClassMethods
      ##
      # Enable multi-environments arguments in a chatops command class.
      # Before enabling it, you have to make sure that the internal logic in the command class
      # is compatible with multi-environments.
      def enable_multi_environments
        @multi_environments_enabled = true
      end
    end
  end
end
