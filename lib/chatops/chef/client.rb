# frozen_string_literal: true

require 'chef'

module Chatops
  module Chef
    class Client
      def initialize(chef_username, chef_key, chef_url)
        @chef_key = chef_key_file(chef_key)
        config = {
          chef_server_url: chef_url,
          client_key: @chef_key.path,
          log_level: 'info',
          log_location: 'STDOUT',
          node_name: chef_username
        }
        ::Chef::Config.from_hash(config)
      end

      def hostnames_from_role(role)
        hostnames = []
        ::Chef::Search::Query.new.search(
          :node, "roles:#{role}"
        ) { |n| hostnames.push(n['hostname']) }
        hostnames
      end

      def ips_from_role(role)
        ips = []
        ::Chef::Search::Query.new.search(
          :node, "roles:#{role}"
        ) { |n| ips.push(n['ipaddress']) }
        ips
      end

      private

      def chef_key_file(chef_key)
        Tempfile.new('chef-pem').tap do |f|
          f.write(chef_key)
          f.flush
        end
      end
    end
  end
end
