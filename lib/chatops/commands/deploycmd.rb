# frozen_string_literal: true

###
# Much of this is lifted from the deploy command.
###

module Chatops
  module Commands
    class Deploycmd
      include Command
      include YamlCmd

      COMMAND_FILE_PATTERN = /\A(\w+)\.yml\z/

      usage "#{command_name} [COMMAND NAME] [ROLE] [OPTIONS]"
      description 'Runs ansible commands across roles in our fleet.'

      options do |o|
        o.bool('--production', 'Run command in the production environment.')
        o.bool('--staging', 'Run command in the staging environment.')
        o.bool('--canary', 'Run command in canary.')
        o.bool('--pre', 'Run command in PRE instead of staging.')
        o.bool('--list', 'List available commands.')
        o.bool('--no-check', 'Run command instead of a dry-run check.')
        o.bool('--skip-haproxy', 'Skip gracefully draining and adding nodes
          from haproxy')
      end

      def perform
        ":unicorn_face: #{execute}"
      end

      def execute
        return list_commands if options[:list]

        command_name, role = arguments

        return 'No command specified.' unless command_name
        return 'No role specified.' unless role
        return unsupported_command unless commands.include?(command_name)

        run_command(command_name, role)
      end

      def run_command(command_name, role)
        vars = {
          CMD: command_name,
          GITLAB_ROLES: role,
          CURRENT_DEPLOY_ENVIRONMENT: environment
        }
        vars[:CHECKMODE] = options[:no_check] ? 'false' : 'true'
        vars[:ANSIBLE_SKIP_TAGS] = 'haproxy' if options[:skip_haproxy]

        response = client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          vars
        )

        "Command `#{command_name}` was issued to "\
          "`#{role}` in `#{environment}`: <#{response.web_url}>"
      rescue StandardError => ex
        "The command could not be run: #{ex.message}"
      end

      def client
        @client ||= Gitlab::Client.new(
          token: gitlab_ops_token,
          host: trigger_host
        )
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

      def environment
        base =
          if options[:production]
            'gprd'
          elsif options[:pre]
            'pre'
          elsif options[:staging]
            'gstg'
          else
            raise 'You must pass an environment name to use this command'
          end

        if options[:canary]
          "#{base}-cny"
        else
          base
        end
      end

      def command_files
        # Get available commands from the yaml files in this folder of the repo
        @command_files ||= client
          .repository_tree('gitlab-com/gl-infra/deploy-tooling', path: 'cmds')
      end
    end
  end
end
