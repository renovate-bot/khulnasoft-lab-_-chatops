# frozen_string_literal: true

module Chatops
  module GitlabEnvironments
    DEV_HOST = 'dev.gitlab.org'
    STAGING_HOST = 'staging.gitlab.com'
    STAGING_REF_HOST = 'staging-ref.gitlab.com'
    OPS_HOST = 'ops.gitlab.net'
    PRE_HOST = 'pre.gitlab.com'
    PRODUCTION_HOST = 'gitlab.com'

    ICONS = {
      'gprd' => 'party-tanuki',
      'gprd-cny' => 'canary',
      'gstg' => 'building_construction',
      'gstg-cny' => 'hatching_chick',
      'gstg-ref' => 'construction',
      'pre' => 'pretzel'
    }.freeze

    def self.define_environment_options(options)
      options.boolean('--dev', "Use #{DEV_HOST}")
      options.boolean('--staging', "Use #{STAGING_HOST}")
      options.boolean('--staging-ref', "Use #{STAGING_REF_HOST}")
      options.boolean('--ops', "Use #{OPS_HOST}")
      options.boolean('--pre', "Use #{PRE_HOST}")
    end

    def env_icon(environment)
      ICONS.fetch(environment, 'question')
    end

    def gitlab_host
      if dev?
        DEV_HOST
      elsif staging?
        STAGING_HOST
      elsif staging_ref?
        STAGING_REF_HOST
      elsif ops?
        OPS_HOST
      elsif pre?
        PRE_HOST
      else
        PRODUCTION_HOST
      end
    end

    def env_name
      if dev?
        'dev'
      elsif staging?
        'gstg'
      elsif staging_ref?
        'gstg-ref'
      elsif ops?
        'ops'
      elsif pre?
        'pre'
      else
        'gprd'
      end
    end

    def gitlab_token
      name =
        if dev?
          'GITLAB_DEV_TOKEN'
        elsif staging?
          'GITLAB_STAGING_TOKEN'
        elsif staging_ref?
          'GITLAB_STAGING_REF_TOKEN'
        elsif ops?
          'GITLAB_OPS_TOKEN'
        elsif pre?
          'GITLAB_PRE_TOKEN'
        else
          'GITLAB_TOKEN'
        end

      env.fetch(name)
    end

    def dev?
      options[:dev]
    end

    def staging?
      options[:staging]
    end

    def staging_ref?
      options[:staging_ref]
    end

    def ops?
      options[:ops]
    end

    def pre?
      options[:pre]
    end

    def production?
      gitlab_host == PRODUCTION_HOST
    end
  end
end
