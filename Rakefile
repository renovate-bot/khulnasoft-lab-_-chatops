# frozen_string_literal: true

require 'rake/clean'

CLEAN.include('coverage')

COMMAND_TEMPLATE = <<~TEMPLATE.strip
  # frozen_string_literal: true

  module Chatops
    module Commands
      class %<class_name>s
        include Command

        description 'Add a short description of the command here.'

        # The "options" method can be used to add additional options (e.g. a
        # --version option). For more information see
        # https://github.com/leejarvis/slop/#usage.
        #
        # If your command does not use any options you should just remove this
        # comment and the block that follows it.
        options do |o|
        end

        def perform
          # This method is called when the command is executed. If this method
          # returns a non-nil value it will be used as the command output
          # (which in turn is sent back to the user).
        end
      end
    end
  end
TEMPLATE

SPEC_TEMPLATE = <<~SPEC_TEMPLATE.strip
  # frozen_string_literal: true

  require 'spec_helper'

  describe Chatops::Commands::%<class_name>s do
    describe '#perform' do
      pending 'You must write tests for the #perform method'
    end
  end
SPEC_TEMPLATE

CI_TEMPLATE = <<~CI_TEMPLATE

%<name>s:
  <<: *chatops
CI_TEMPLATE

desc 'Runs all the tests'
task :test do
  sh 'rspec spec --order random'
end

desc 'Runs all the tests with code coverage enabled'
task :coverage do
  ENV['COVERAGE'] = '1'

  Rake::Task['test'].invoke
end

desc 'Generates a new command'
task :generate, :name do |_, args|
  abort('You must specify the name of the command') unless args[:name]

  class_name = args[:name]
    .split('_')
    .map(&:capitalize)
    .join

  command_template = format(COMMAND_TEMPLATE, class_name: class_name)
  spec_template = format(SPEC_TEMPLATE, class_name: class_name)

  lib_dir = File.expand_path('lib', __dir__)
  spec_dir = File.expand_path('spec', __dir__)

  cmd_path = "chatops/commands/#{args[:name]}.rb"
  spec_path = "chatops/commands/#{args[:name]}_spec.rb"

  File.open(File.join(lib_dir, 'chatops.rb'), 'a') do |handle|
    handle.puts("require 'chatops/commands/#{args[:name]}'")
  end

  File.open(File.join(lib_dir, cmd_path), 'w') do |handle|
    handle.write(command_template)
  end

  File.open(File.join(spec_dir, spec_path), 'w') do |handle|
    handle.write(spec_template)
  end

  File.open(File.expand_path('.gitlab-ci.yml', __dir__), 'a') do |handle|
    handle.write(format(CI_TEMPLATE, name: args[:name]))
  end

  puts "The new command can be found at lib/#{cmd_path}, don't forget to add " \
    "tests in spec/#{spec_path}!"
end
