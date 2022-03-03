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
    add_group 'PagerDuty', 'lib/chatops/pager_duty'
    add_group 'Slack', 'lib/chatops/slack'
    add_group 'HAProxy', 'lib/chatops/haproxy'
    add_group 'Chef', 'lib/chatops/chef'
  end

  SimpleCov.start
end

require 'chatops'
require 'climate_control'
require 'stringio'
require 'timecop'
require 'rspec-parameterized'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.color = true
end

# To be 100% sure production secrets aren't accidentally used for tests we wipe
# any variable ending with "_TOKEN" (e.g. "GITLAB_TOKEN"). We also wipe out
# database related environment variables.
secret_vars = ENV.keys.select do |key|
  key.end_with?('_TOKEN', '_KEY') || key.start_with?('DATABASE_')
end
secret_vars.each { |var| ENV.delete(var) }
