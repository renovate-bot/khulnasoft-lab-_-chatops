# frozen_string_literal: true

module Chatops
  module GitlabEnvironments
    DEV_HOST = 'dev.gitlab.org'
    STAGING_HOST = 'staging.gitlab.com'
    OPS_HOST = 'ops.gitlab.net'
    PRODUCTION_HOST = 'gitlab.com'

    ICONS = {
      'gprd' => 'party-tanuki',
      'gprd-cny' => 'canary',
      'gstg' => 'building_construction'
    }.freeze

    def self.define_environment_options(options)
      options.boolean('--dev', "Use #{DEV_HOST}")
      options.boolean('--staging', "Use #{STAGING_HOST}")
      options.boolean('--ops', "Use #{OPS_HOST}")
    end

    def env_icon(environment)
      ICONS.fetch(environment, 'question')
    end

    def gitlab_host
      if dev?
        DEV_HOST
      elsif staging?
        STAGING_HOST
      elsif ops?
        OPS_HOST
      else
        PRODUCTION_HOST
      end
    end

    def env_name
      if dev?
        'dev'
      elsif staging?
        'gstg'
      elsif ops?
        'ops'
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
        elsif ops?
          'GITLAB_OPS_TOKEN'
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

    def ops?
      options[:ops]
    end

    def production?
      gitlab_host == PRODUCTION_HOST
    end
  end
end
