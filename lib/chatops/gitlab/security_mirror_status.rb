# frozen_string_literal: true

module Chatops
  module Gitlab
    # Represents the Canonical -> Security -> Build mirror status of one project
    class SecurityMirrorStatus
      # Hash of the Canonical project properties
      attr_reader :canonical

      # Hash of the Security project properties
      attr_reader :security

      # project - Hash of a Security project from the Group API
      def initialize(project)
        @canonical = project['forked_from_project']
        @canonical_path = @canonical['path_with_namespace']

        @security = project
        @security_path = @security['path_with_namespace']
      end

      # Checks if the status is available
      #
      # Because the API is currently behind a project feature flag, not all
      # projects have it.
      def available?
        @available ||= security_status && build_status
      end

      # Error String for the Canonical -> Security mirror, if any
      def security_error
        security_status.last_error&.sub('on the remote', 'on Security')
      end

      def security_mirrored?
        security_error.nil? && security_status.enabled
      end

      # Error String for the Security -> Build mirror, if any
      def build_error
        build_status.last_error&.sub('on the remote', 'on Build')
      end

      def build_mirrored?
        build_error.nil? && build_status.enabled
      end

      def complete?
        security_mirrored? && build_mirrored?
      end

      def canonical_link
        "<https://gitlab.com/#{@canonical_path}|Canonical>"
      end

      def security_link
        [
          mirror_icon(security_status),
          "<https://gitlab.com/#{@security_path}|Security>"
        ].join(' ')
      end

      def build_link
        [
          mirror_icon(build_status),
          # Extract the Build project path from the mirror URL
          "<https://#{build_status.url.sub(/\A.*@(.*)\.git\z/, '\1')}|Build>"
        ].join(' ')
      end

      def mirror_chain
        [
          canonical_link,
          security_link,
          build_link,
          complete? ? ':white_check_mark:' : ':warning:'
        ].join(' ')
      end

      private

      def client
        @client ||= ::Chatops::Gitlab::Client
          .new(token: ENV.fetch('GITLAB_TOKEN'))
          .internal_client
      end

      # Fetch the remote mirror status for Canonical -> Security
      def security_status
        # NOTE: This API is experimental and isn't yet in the gem
        @security_status ||= client
          .get("/projects/#{client.url_encode(@canonical_path)}/remote_mirrors")
          .detect { |m| m.url.include?('/security/') }
      rescue ::Gitlab::Error::NotFound
        # Feature flag is disabled on this project
        false
      end

      # Fetch the remote mirror status for Security -> Build
      def build_status
        # NOTE: This API is experimental and isn't yet in the gem
        @build_status ||= client
          .get("/projects/#{client.url_encode(@security_path)}/remote_mirrors")
          .detect { |m| m.url.include?('dev.gitlab.org') }
      rescue ::Gitlab::Error::NotFound
        # Feature flag is disabled on this project
        false
      end

      def mirror_icon(status)
        if status.last_error
          ':x:'
        elsif !status.enabled
          ':double_vertical_bar:' # Otherwise known as Pause
        else
          ':arrow_right:'
        end
      end
    end
  end
end
