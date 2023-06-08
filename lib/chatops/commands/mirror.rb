# frozen_string_literal: true

module Chatops
  module Commands
    class Mirror
      include ::SemanticLogger::Loggable
      include Command

      RepositoriesOutOfSync = Class.new(StandardError)

      COMMANDS = Set.new(%w[status])

      options do |o|
        o.separator <<~AVAIL.chomp

          Available subcommands:

          #{available_subcommands}
        AVAIL

        o.separator <<~HELP.chomp

          Examples:

            Check the status of all Security mirrors:

              status
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

      def status
        post_general_status

        return unless security_release_pipeline?

        logger.info('Running as part of a security pipeline')

        post_job_status

        raise RepositoriesOutOfSync unless synced_repositories?
      end

      private

      def security_mirrors
        @security_mirrors ||= client
          .group_projects('gitlab-org/security', include_subgroups: true)
          .auto_paginate
          .map(&:to_h)
          .select { |p| p.key?('forked_from_project') }
          .sort_by { |p| p['path'] }
          .map { |p| Gitlab::SecurityMirrorStatus.new(p) }
          .select(&:available?)
      end

      def mirror_message
        Slack::MirrorMessage.new(
          security_mirrors: security_mirrors,
          env: env
        )
      end

      def post_general_status
        mirror_message.general_status
      end

      def post_job_status
        mirror_message.job_status(synced_repositories: synced_repositories?)
      end

      def synced_repositories?
        security_mirrors.all?(&:complete?)
      end

      def security_release_pipeline?
        env.fetch('SECURITY_RELEASE_PIPELINE', nil)
      end

      def client
        @client ||= Gitlab::Client.new(token: gitlab_token)
      end
    end
  end
end
