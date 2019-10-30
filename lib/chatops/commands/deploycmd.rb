# frozen_string_literal: true

###
# Much of this is lifted from the deploy command.
###

module Chatops
  module Commands
    class Deploycmd
      include Command

      usage "#{command_name} [COMMAND NAME] [ROLE] [OPTIONS]"
      description 'Runs ansible commands across roles in our fleet.'

      options do |o|
        o.bool('--production', 'Run command in production instead of staging.')
        o.bool('--dr', 'Run command in DR instead of staging.')
        o.bool('--canary', 'Run command in canary.')
        o.bool('--pre', 'Run command in PRE instead of staging.')
        o.bool('--list', 'List available commands.')
        o.bool('--check', 'Run command in check mode and make no changes.')
      end

      def perform
        command_list = fetch_commands
        return list_commands(command_list) if options[:list]

        return 'No command specified.' unless command_name = arguments[0]

        return "#{command_name} is not a known command." unless
          command_list.include?(command_name)

        return 'No role specified.' unless role = arguments[1]

        run_command(command_name, role)
      end

      def list_commands(command_list)
        "Valid known commands are:#{command_list.join(', ')}."
      end

      def run_command(command_name, role)
        vars = {
          'CMD': command_name,
          'GITLAB_ROLE': role,
          'CURRENT_DEPLOY_ENVIRONMENT': environment,
          'CHECKMODE': '--check'
        }
        response = client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          vars
        )

        url = response.web_url

        "Command #{command_name} was issued to "\
        "#{role} in #{environment}: <#{url}>"
      rescue StandardError => error
        "The command could not be run: #{error.message}"
      end

      def client
        # For triggers we don't need an API token, so we explicitly set it to
        # nil.
        @client ||= Gitlab::Client.new(token: nil, host: trigger_host)
      end

      def trigger_token
        env.fetch('COMMAND_TRIGGER_TOKEN')
      end

      def trigger_project
        env.fetch('COMMAND_TRIGGER_PROJECT')
      end

      def trigger_host
        env.fetch('COMMAND_TRIGGER_HOST')
      end

      def gitlab_ops_token
        env.fetch('GITLAB_OPS_TOKEN')
      end

      def environment
        base =
          if options[:production]
            'gprd'
          elsif options[:pre]
            'pre'
          elsif options[:dr]
            'dr'
          else
            'gstg'
          end

        if options[:canary]
          "#{base}-cny"
        else
          base
        end
      end

      def fetch_commands
        commands = []
        file_list = Gitlab::Client
          .new(token: gitlab_ops_token, host: trigger_host)
          .repository_tree('157', path: 'cmds')
        file_list.each do |key|
          if match = key.name.match(/^(\w+)\.yml$/)
            commands.push(match.captures[0])
          end
        end
        commands
      end
    end
  end
end
