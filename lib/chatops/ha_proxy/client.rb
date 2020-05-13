# frozen_string_literal: true

module Chatops
  module HAProxy
    # HAProxy manages servers in HAProxy by
    # sending commands over the admin socket
    class Client
      SERVER_INDEX = 1 # svname
      STATE_INDEX = 17 # status
      WEIGHT_INDEX = 18 # weight
      CONNECTION_INDEX = 4 # scur
      BACKEND_INDEX = 0 # pxname
      LB_ADMIN_PORT = 23_646
      MAINT_STATE = 'MAINT'
      DRAIN_STATE = 'DRAIN'
      UP_STATE = 'UP'

      def initialize(lbs:)
        @lbs = lbs
      end

      def set_server_state(server_stats:, state:)
        server_stats.each do |s|
          sock = TCPSocket.new(s[:lb_ip], LB_ADMIN_PORT)
          begin
            haproxy_send(
              cmd: "set server #{s[:backend]}/#{s[:server]} state #{state}",
              sock: sock
            )
          ensure
            sock.close
          end
        end
      end

      # Returns a hash of server information from all lbs
      def server_stats
        server_data = []
        @lbs.each do |lb_ip|
          sock = TCPSocket.new(lb_ip, LB_ADMIN_PORT)
          haproxy_send(cmd: 'show stat', sock: sock)

          haproxy_gets(sock: sock) do |line|
            line_stats = line.split(',')
            next if line_stats.empty?
            # since we only care about server statuses, skip lines when
            # the server is not a node
            # lines like these will be skipped:
            #   api_rate_limit,localhost,0,0,13,30,,208734,178279435,1164 ...
            #   ssh,BACKEND,0,0,0,3,5000,2079,1537705,2894066,0,0,,0,10,0, ...
            #   check_ssh,FRONTEND,,,0,1,50000,119259,7155540,17411814,0,0...
            next if %w[BACKEND FRONTEND localhost]
              .include?(line_stats[SERVER_INDEX])

            server_data.push(
              state: line_stats.fetch(STATE_INDEX),
              conn: line_stats.fetch(CONNECTION_INDEX),
              server: line_stats.fetch(SERVER_INDEX),
              backend: line_stats.fetch(BACKEND_INDEX),
              lb_ip: lb_ip,
              weight: line_stats.fetch(WEIGHT_INDEX)
            )
          end

          sock.close
        end
        server_data
      end

      private

      def haproxy_send(cmd:, sock:)
        sock.write("#{cmd}\n")
      end

      def haproxy_gets(sock:)
        while (line = sock.gets&.strip)
          yield line unless line.start_with?('#')
        end
      end
    end
  end
end
