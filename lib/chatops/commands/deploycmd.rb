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
        o.bool('--no-check', 'Run command instead of a dry-run check.')
        o.bool('--skip-haproxy', 'Skip gracefully draining and adding nodes
          from haproxy')
      end

      def perform
        command_list = fetch_commands
        return list_commands if
          options[:list]

        return 'No command specified.' unless (command_name = arguments[0])

        return 'No role specified.' unless (role = arguments[1])

        return unsupported_command unless
          command_list.include?(command_name)

        run_command(command_name, role)
      end

      def list_commands
        vals = fetch_commands.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          :unicorn_face: The following commands are available:

          #{list}

          For more information run `deploycmd --help`.
        HELP
      end

      def unsupported_command
        vals = fetch_commands.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~HELP.strip
          :unicorn_face: The provided command is invalid. The following commands are available:

          #{list}

          For more information run `deploycmd --help`.
        HELP
      end

      def run_command(command_name, role)
        vars = {
          'CMD': command_name,
          'GITLAB_ROLE': role,
          'CURRENT_DEPLOY_ENVIRONMENT': environment
        }
        vars[:CHECKMODE] = '--check' unless options[:no_check]
        vars[:ANSIBLE_SKIP_TAGS] = 'haproxy' if options[:skip_haproxy]
        response = client.run_trigger(
          trigger_project,
          trigger_token,
          :master,
          vars
        )

        url = response.web_url

        ":unicorn_face: Command `#{command_name}` was issued to "\
        "`#{role}` in `#{environment}`: <#{url}>"
      rescue StandardError => error
        ":unicorn_face: The command could not be run: #{error.message}"
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

      def repository_tree
        @repository_tree ||= Gitlab::Client
          .new(token: gitlab_ops_token, host: trigger_host)
          .repository_tree(
            'gitlab-com/gl-infra/deploy-tooling',
            path: 'cmds'
          )
      end

      def fetch_commands
        return @fetch_commands unless @fetch_commands.nil?

        commands = []
        name_regex = /^(?<name>\w+)\.yml$/
        repository_tree.each do |key|
          if (match = key.name.match(name_regex))
            commands.push(match[:name])
          end
        end
        commands
      end
    end
  end
end
