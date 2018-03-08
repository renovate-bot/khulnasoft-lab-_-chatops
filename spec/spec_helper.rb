# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'

  SimpleCov.configure do
    root File.expand_path('../', __dir__)
    command_name 'rspec'
    project_name 'chatops'

    add_filter 'spec'
    add_filter 'vendor'

    add_group 'Commands', 'lib/chatops/commands'
    add_group 'Database', 'lib/chatops/database'
    add_group 'Grafana', 'lib/chatops/grafana'
    add_group 'Markdown', 'lib/chatops/markdown'
    add_group 'Slack', 'lib/chatops/slack'
  end

  SimpleCov.start
end

require 'chatops'
require 'stringio'

RSpec.configure do |config|
  config.color = true
end
