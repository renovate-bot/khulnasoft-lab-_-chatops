# frozen_string_literal: true

module Chatops
  module Commands
    class Canary
      DRAIN_INTERVAL = 60 # Wait 60 seconds for connections to drain
      include Command
      include HAProxy::Disp
      include GitlabEnvironments

      usage "#{command_name} [OPTIONS]"
      description 'Controls canary traffic'
      options do |o|
        o.bool('--production',
               'Control production canary traffic')
        o.bool('--staging',
               'Control staging canary traffic')
        o.bool('--ready',
               'Set canary to enable connections')
        o.bool('--enable',
               'Set canary to enable connections (same as --ready)')
        o.bool('--drain',
               'Set canary to drain connections')
        o.bool('--maint',
               'Set canary to be in maint state')
        o.bool('--disable',
               'Set canary to be disabled, drains and then sets maint state')
        o.bool('--ignore-deployment-check',
               'Ignores the deployment check, ' \
                'do not use this option unless you know what you are doing!')
      end

      # rubocop: disable Metrics/CyclomaticComplexity
      def perform
        unless staging? ^ production?
          return '_You need to specify the environment with ' \
            '`--staging` or `--production`._'
        end

        # If there is a new state transition, make it here. Otherwise
        # we just print the status and a note about usage
        server_state_commands.each do |state|
          if !options[:ignore_deployment_check] &&
             reduce_canary_traffic?(state) &&
             canary_active_deployment?
            return [
              'Unable to set canary state because there is a ' \
                "<#{chef_client.canary_pipeline_url(env: env_name)}|" \
                'canary deploy in progress>.',
              'Draining canary while there is a deploy will cause errors for ' \
                'users connecting to canary hosts.',
              'If you are sure you want to proceed anyway, use the ' \
                '`--ignore-deployment-check` option.'
            ].join("\n")
          end

          canary_server_state!(
            state: state
          )
          if options[:disable] &&
             state == Chatops::HAProxy::State::DRAIN
            sleep(DRAIN_INTERVAL)
          end

          send_event("Canary set to #{state}")
        end

        # tweet tweet tweet - helps to identify that the response is canary
        (usage_disp + [':canary: :canary: :canary:'] +
          backend_stats_disp(servers: canary_servers) +
          server_disp(servers: canary_servers, hide_healthy: false)).join("\n")
      end
      # rubocop: enable Metrics/CyclomaticComplexity

      def chef_client
        @chef_client ||= Chatops::Chef::Client.new
      end

      def usage_disp
        # display some additional text if no options are
        # specifified
        return [] unless options.to_hash.reject { |k| %i[production staging].include?(k) }.empty?

        ['_Use `/chatops run canary --help` to list canary commands_',
         'Displaying the current canary status:']
      end

      def server_state_commands
        if options[:ready] || options[:enable]
          [Chatops::HAProxy::State::READY]
        elsif options[:disable]
          [Chatops::HAProxy::State::DRAIN, Chatops::HAProxy::State::MAINT]
        elsif options[:drain]
          [Chatops::HAProxy::State::DRAIN]
        elsif options[:maint]
          [Chatops::HAProxy::State::MAINT]
        else
          []
        end
      end

      def reduce_canary_traffic?(state)
        # Any state that will reduce canary traffic
        # these state transitions are dangerous if a deploy is in progress
        [Chatops::HAProxy::State::DRAIN,
         Chatops::HAProxy::State::MAINT].include?(state)
      end

      def canary_server_state!(state:)
        haproxy_client.set_server_state(
          server_stats: canary_stats,
          state: state
        )
      end

      def canary_stats
        haproxy_client.server_stats.select do |s|
          canary_server_name?(s[:server])
        end
      end

      def canary_servers
        haproxy_client.server_stats.select do |s|
          canary_server_name?(s[:server]) && s[:weight].to_i.positive?
        end
      end

      def canary_server_name?(server)
        # By convention, all canary server
        # names have the identifier '-cny-'
        # in the name
        server.include?('-cny-')
      end

      def haproxy_client
        @haproxy_client ||= Chatops::HAProxy::Client.new(lbs: lb_ips)
      end

      def lb_ips
        @lb_ips ||= chef_client.ips_from_role("#{env_name}-base-lb")
      end

      def send_event(message)
        return unless staging? || production?

        Chatops::Events::Client
          .new(env_name)
          .send_event(
            message
          )
      end

      def canary_active_deployment?
        @canary_active_deployment ||= chef_client.canary_active_deployment?(env: env_name)
      end

      def production?
        options[:production]
      end
    end
  end
end
