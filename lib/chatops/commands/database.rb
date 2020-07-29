# frozen_string_literal: true

module Chatops
  module Commands
    class Database
      include Command
      include YamlCmd

      usage "#{command_name} SUBCOMMAND [OPTIONS]"
      description 'Executes db-ops commands'

      options do |o|
        o.bool('--production', 'Run command in production instead of staging.')
        o.bool('--list', 'List available commands.')
      end

      def perform
        ":database: #{execute}"
      end

      def execute
        return list_commands if options[:list]

        command = arguments[0]

        return 'No command specified.' unless command
        return unsupported_command unless commands.include?(command)

        response = run_trigger(command)

        "Command `#{command}` was issued in `#{environment}`: " \
          "<#{response.web_url}>"
      rescue StandardError => error
        "The command could not be run: #{error.message}"
      end

      def trigger_token
        env.fetch('DATABASE_TRIGGER_TOKEN')
      end

      def trigger_project
        env.fetch('DATABASE_TRIGGER_PROJECT')
      end

      def trigger_host
        env.fetch('DATABASE_TRIGGER_HOST')
      end

      def environment
        if options[:production]
          'gprd'
        else
          'gstg'
        end
      end

      private

      def run_trigger(command)
        client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          'CMD': command,
          'DB_OPS_ENV': environment
        )
      end

      def client
        @client ||= Gitlab::Client.new(
          token: gitlab_ops_token,
          host: trigger_host
        )
      end

      def command_files
        # Get available commands from the yaml files in this folder of the repo
        @command_files ||= client.repository_tree(
          'gitlab-com/gl-infra/db-ops',
          path: 'ansible/playbooks'
        )
      end
    end
  end
end
