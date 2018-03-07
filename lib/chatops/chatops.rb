# frozen_string_literal: true

module Chatops
  CommandError = Class.new(StandardError)

  # The name of the trace section to wrap output in.
  SECTION = 'chat_reply'

  # All commands that have been registered and should thus be available to the
  # user.
  def self.commands
    @commands ||= {}
  end

  # Runs a chatops command.
  #
  # argv - The commandline arguments that were used to invoke the program.
  # env - The environment variables to use for obtaining the chat input.
  def self.run(argv = [], env = {})
    name = argv.fetch(0) do
      raise(
        CommandError,
        'You must define a command to execute in .gitlab-ci.yml'
      )
    end

    chat_input = env.fetch('CHAT_INPUT') do
      raise(
        CommandError,
        'The CHAT_INPUT environment variable must be set to a string acting ' \
          'as the arguments for the command'
      )
    end

    command_class = commands[name]

    unless command_class
      raise CommandError, "The command #{name.inspect} does not exist"
    end

    command_class.perform(chat_input.split, env)
  end

  # Wraps the output of the block in a custom trace section. This allows us to
  # get rid of the "before_script" output in the least hacky way.
  def self.with_trace_section
    puts "section_start:#{Time.now.to_i}:#{SECTION}\r\033[0K"

    yield
  ensure
    puts "section_end:#{Time.now.to_i}:#{SECTION}\r\033[0K"
  end
end
