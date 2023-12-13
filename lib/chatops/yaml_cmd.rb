# frozen_string_literal: true

module Chatops
  module YamlCmd
    COMMAND_FILE_PATTERN = /\A(\w+)\.yml\z/

    def list_commands
      <<~HELP.strip
        The following commands are available:

        #{md_commands}

        For more information run `#{self.class.command_name} --help`.
      HELP
    end

    def unsupported_command
      <<~HELP.strip
        The provided command is invalid. The following commands are available:

        #{md_commands}

        For more information run `#{self.class.command_name} --help`.
      HELP
    end

    def commands
      @commands ||=
        command_files
          .select { |file| file.name.match?(COMMAND_FILE_PATTERN) }
          .map { |file| file.name.gsub(COMMAND_FILE_PATTERN, '\1') }
    end

    def md_commands
      vals = commands.to_a.sort.map { |name| Markdown::Code.new(name) }

      Markdown::List.new(vals)
    end

    def command_files
      raise NotImplementedError
    end
  end
end
