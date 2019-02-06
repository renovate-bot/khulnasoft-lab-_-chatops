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
        o.string('--backend',
                 'Filter by a specific backend')
      end

      def perform
        lb_ips = chef_client.ips_from_role("#{chef_env}-base-lb")
        haproxy_client = Chatops::HAProxy::Client.new(lbs: lb_ips)

        # All hostnames that have the cny-omnibus-version role, which
        # means they are configured to use the canary version of the
        # omnibus
        cny_hostnames = chef_client.hostnames_from_role(
          "#{chef_env}-cny-omnibus-version"
        )

        # If there is a new state transition, make it here. Otherwise
        # we just print the status and a note about usage
        if server_state_command
          haproxy_client.set_server_state(
            servers: cny_hostnames,
            backend: options[:backend],
            state: server_state_command
          )
        end

        # Trim the full list of servers to just the canary servers
        # and remove servers with a weight of zero as they are not
        # taking any traffic
        cny_servers = haproxy_client.server_stats.select do |s|
          cny_hostnames.include?(s[:server]) && s[:weight].to_i.positive?
        end

        # tweet tweet tweet - helps to identify that the response is canary
        (usage_disp + [':canary: :canary: :canary:'] +
          backend_stats_disp(servers: cny_servers) +
          server_disp(servers: cny_servers, hide_healthy: false)).join("\n")
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

      def chef_env
        options[:production] ? 'gprd' : 'gstg'
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
    end
  end
end
