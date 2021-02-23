# frozen_string_literal: true

require 'chef'

module Chatops
  module Chef
    class Client
      DEFAULT_CHEF_URL = 'https://chef.gitlab.com/organizations/gitlab'

      def initialize
        key = key_file(pem_key)
        config = {
          chef_server_url: url,
          client_key: key.path,
          log_level: 'info',
          log_location: 'STDOUT',
          node_name: username
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

      def package_version(role)
        ::Chef::Role.load("#{role}-omnibus-version")
          .default_attributes
          .dig('omnibus-gitlab', 'package', 'version') || 'unknown'
      end

      private

      def key_file(key)
        Tempfile.new('chef-pem').tap do |f|
          f.write(key)
          f.flush
        end
      end

      # Chef pem for authenticating with the Chef server
      def pem_key
        ENV.fetch('CHEF_PEM_KEY')
      end

      # Chef username for interacting with the chef server
      def username
        ENV.fetch('CHEF_USERNAME')
      end

      # Chef endpoint, defaults to GitLab's chef server
      def url
        ENV.fetch('CHEF_URL', DEFAULT_CHEF_URL)
      end
    end
  end
end
