# frozen_string_literal: true

module Chatops
  module Commands
    class Annotate
      include Command
      include GitlabEnvironments

      usage "#{command_name} [TEXT] [OPTIONS]"
      description 'Create a custom Grafana annotation.'

      options do |o|
        GitlabEnvironments.define_environment_options(o)
      end

      def perform
        annotation = arguments[0]

        unless annotation && !annotation.empty?
          return 'You need to provide text to create an annotation'
        end

        Grafana::Annotate.new(token: grafana_token)
          .annotate!("#{annotation} (by #{username})", tags: [env_name])
      end

      def username
        env.fetch('GITLAB_USER_LOGIN')
      end
    end
  end
end
