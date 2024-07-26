# frozen_string_literal: true

require 'diplomat'
require 'json'

module Chatops
  module Consul
    class Client
      class KeyNotFoundError < StandardError; end

      def initialize
        consul_host = ENV.fetch('CONSUL_HOST', 'localhost')
        consul_port = ENV.fetch('CONSUL_PORT', '8500')

        # Configure Diplomat with the specified host and port
        Diplomat.configure do |config|
          config.url = "http://#{consul_host}:#{consul_port}"
        end
      end

      def put(key, json_string)
        # Store the JSON string in the specified Consul key
        Diplomat::Kv.put(key, json_string)
      end

      def get(key)
        Diplomat::Kv.get(key)
      rescue Diplomat::KeyNotFound
        raise KeyNotFoundError, "The key '#{key}' was not found in Consul"
      end
    end
  end
end
