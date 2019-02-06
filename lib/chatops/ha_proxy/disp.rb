# frozen_string_literal: true

module Chatops
  module HAProxy
    module Disp
      def backend_stats_disp(servers:)
        server_stat_disp =
          server_stats_by_backend(servers: servers)
            .sort.to_h.map do |backend, stats|
            "#{backend.ljust(20)}: " \
                "#{stats.to_a.map { |stat| stat.join(':') }.join(' ')}"
          end
        ['```'] + server_stat_disp + ['```']
      end

      def server_disp(servers:, hide_healthy: true)
        servers_not_up = Hash.new { |h, k| h[k] = Set.new }
        servers.each do |s|
          unless s[:state] == 'UP' && hide_healthy
            servers_not_up[s[:state]].add(s[:server])
          end
        end
        servers_not_up.sort.map do |(state, srvs)|
          "*#{state}*: #{srvs.to_a.join(', ')}"
        end
      end

      def server_stats_by_backend(servers:)
        backends = {}

        servers.group_by { |h| h[:backend] }.each do |backend, backend_servers|
          backend_servers.each do |s|
            backends[backend] ||= Hash.new(0)
            backends[backend][:conn] += s[:conn].to_i
            backends[backend][s[:state]] += 1
          end
        end

        backends
      end
    end
  end
end
