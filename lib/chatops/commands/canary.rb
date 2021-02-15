# frozen_string_literal: true

module Chatops
  module Commands
    class Canary
      DRAIN_INTERVAL = 60 # Wait 60 seconds for connections to drain
      include Command
      include HAProxy::Disp
      include Chef::Config
      include GitlabEnvironments

      usage "#{command_name} [OPTIONS]"
      description 'Controls canary traffic'
      options do |o|
        o.bool('--production',
               'Control production canary traffic instead of staging')
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
      end

      def perform
        # If there is a new state transition, make it here. Otherwise
        # we just print the status and a note about usage
        server_state_commands.each do |state|
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

      def chef_client
        @chef_client ||= Chatops::Chef::Client.new(
          chef_username, chef_pem_key, chef_url
        )
      end

      def usage_disp
        # display some additional text if no options are
        # specifified
        return [] unless options.empty?

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
    end
  end
end
