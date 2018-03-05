# frozen_string_literal: true

module Chatops
  module Commands
    # Shows information about the available commands.
    class Help
      include Command

      description 'Shows information about the available commands'

      def perform
        values = sorted_command_classes.map do |klass|
          name = Markdown::Code.new(klass.command_name)

          "#{name}: #{klass.description}"
        end

        commands = Markdown::List.new(values)

        "The following commands are available:\n\n#{commands}\n\n" \
          'For more information about a command you can it and pass the ' \
          '--help option.'
      end

      def sorted_command_classes
        Chatops.commands.values.sort_by(&:command_name)
      end
    end
  end
end
