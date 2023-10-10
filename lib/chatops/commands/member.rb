# frozen_string_literal: true

module Chatops
  module Commands
    class Member
      include Command
      include GitlabEnvironments

      usage "#{command_name} [COMMAND] [ARGUMENTS] [OPTIONS]"
      description 'Adds or removes a user from a project or group.'

      COMMANDS = Set.new(%w[add remove]).freeze

      ACCESS_LEVELS = {
        'guest' => 10,
        'reporter' => 20,
        'developer' => 30,
        'maintainer' => 40
      }.freeze

      options do |o|
        o.string('--level', 'The access level to use', default: 'developer')

        GitlabEnvironments.define_environment_options(o)

        o.separator <<~EXAMPLES.chomp

          Examples:

            Adding user "alice" to project "gitlab-org/gitlab-foss":

              member add alice gitlab-org/gitlab-foss

            Adding user "alice" to project "gitlab-org/gitlab-foss" as a reporter:

              member add --level reporter alice gitlab-org/gitlab-foss

            Adding user "alice" to group "gitlab-org":

              member add alice gitlab-org

            Removing user "alice" from project "gitlab-org/gitlab-foss":

              member remove alice gitlab-org/gitlab-foss
        EXAMPLES
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      rescue ::Gitlab::Error::ResponseError => e
        "Failed to #{command} #{username!}: #{e.response_message}"
      rescue ArgumentError => e
        "Failed to #{command} #{username!}: #{e.message}"
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The subcommand is invalid. The following subcommands are available:

          #{list}

          For more information run `member --help`.
        MESSAGE
      end

      def add
        level = access_level!
        user = find_user!
        entity = find_group_or_project!

        entity.add_user(user, level)

        "#{username!} has been added to #{project_or_group_name!}"
      end

      def remove
        user = find_user!
        entity = find_group_or_project!

        entity.remove_user(user)

        "#{username!} has been removed from #{project_or_group_name!}"
      end

      def username!
        arguments.fetch(1) do
          raise ArgumentError, 'You must specify a username'
        end
      end

      def project_or_group_name!
        arguments.fetch(2) do
          raise ArgumentError, 'You must specify a project or group name'
        end
      end

      def access_level!
        ACCESS_LEVELS.fetch(options[:level]) do
          raise ArgumentError, 'The access level is invalid'
        end
      end

      def find_user!
        client.find_user(username!) ||
          raise(ArgumentError, 'The user does not exist')
      end

      def find_group_or_project!
        Gitlab::Group.new(client.find_group(project_or_group_name!), client)
      rescue ::Gitlab::Error::NotFound
        begin
          Gitlab::Project
            .new(client.find_project(project_or_group_name!), client)
        rescue ::Gitlab::Error::NotFound
          raise ArgumentError, 'The group or project does not exist'
        end
      end

      def client
        @client ||= Gitlab::Client.new(token: environment.gitlab_token, host: environment.gitlab_host)
      end
    end
  end
end
