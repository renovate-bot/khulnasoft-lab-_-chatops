# frozen_string_literal: true

module Chatops
  module Commands
    class Canary
      include Command
      include HAProxy::Disp
      include Chef::Config

      usage "#{command_name} [OPTIONS]"
      description 'Controls canary traffic'
      options do |o|
        o.bool('--production',
               'Control production canary traffic instead of staging')
        o.bool('--ready',
               'Set canary to enable connections')
        o.bool('--drain',
               'Set canary to drain connections')
        o.bool('--maint',
               'Set canary to be disabled')
      end

      def perform
        # If there is a new state transition, make it here. Otherwise
        # we just print the status and a note about usage
        if server_state_command
          canary_server_state!(
            state: server_state_command
          )
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
        return [] if server_state_command

        ['_Use `/chatops run canary --help` to list canary commands_',
         'Displaying the current canary status:']
      end

      def server_state_command
        if options[:ready]
          'ready'
        elsif options[:drain]
          'drain'
        elsif options[:maint]
          'maint'
        end
      end

      def canary_server_state!(state:)
        stats = haproxy_client.server_stats.select do |s|
          canary_server_name?(s[:server])
        end

        haproxy_client.set_server_state(
          server_stats: stats,
          state: state
        )
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
        @lb_ips ||= chef_client.ips_from_role("#{chef_env}-base-lb")
      end

      def chef_env
        options[:production] ? 'gprd' : 'gstg'
      end
    end
  end
end
