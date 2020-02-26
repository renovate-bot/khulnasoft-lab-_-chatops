# frozen_string_literal: true

module Chatops
  module Command
    attr_reader :arguments, :options, :env

    # by - The class this module was included into.
    def self.included(mod)
      mod.extend(ClassMethods)

      Chatops.commands[mod.command_name] = mod
    end

    def initialize(arguments = [], options = {}, env = {})
      @arguments = arguments
      @options = options
      @env = env.to_hash
    end

    def perform
      raise(
        NotImplementedError,
        'Your command must implement the #perform method'
      )
    end

    # Returns the ID of the chat channel the command was triggered in.
    def channel
      env.fetch('CHAT_CHANNEL')
    end

    # Returns the API token to use for interacting with the Slack API.
    def slack_token
      env.fetch('SLACK_TOKEN')
    end

    # Returns the API token to use for interacting with the GitLab API.
    def gitlab_token
      env.fetch('GITLAB_TOKEN')
    end

    def gitlab_ops_token
      env.fetch('GITLAB_OPS_TOKEN')
    end

    # Returns the API token to use for interacting with the Grafana API.
    def grafana_token
      env.fetch('GRAFANA_TOKEN')
    end

    # Returns the API token to use for interacting with the PagerDuty API.
    def pagerduty_token
      env.fetch('PAGERDUTY_TOKEN')
    end

    module ClassMethods
      def command_name
        @command_name ||= name
          .to_s.split('::')
          .last
          .gsub(/([a-z])([A-Z])/, '\1_\2')
          .downcase
      end

      # Stores a block that can be used for specifying custom option flags,
      # banners, etc.
      def options(&block)
        @options_block = block
      end

      # Sets a description for the current command class.
      def description(value = nil)
        if value
          @description = value
        else
          @description
        end
      end

      def usage(value = nil)
        if value
          @usage = value
        else
          @usage || "#{command_name} [OPTIONS]"
        end
      end

      # Executes the command.
      #
      # argv - The arguments parse.
      # env - The environment variables to pass to the command.
      def perform(argv = [], env = {})
        opts = Slop.parse(argv) do |o|
          o.banner = "#{@description}\n\nUsage: #{usage}"

          o.separator "\nOptions:\n"

          o.on('-h', '--help', 'Shows this help message') do
            return Markdown::Code.new(o.to_s(prefix: '  ')).to_s
          end

          @options_block&.call(o)
        end

        new(opts.arguments, opts.to_hash, env).perform
      end
    end
  end
end
