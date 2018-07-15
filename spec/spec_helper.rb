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

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.color = true
end

# To be 100% sure production secrets aren't accidentally used for tests we wipe
# any variable ending with "_TOKEN" (e.g. "GITLAB_TOKEN"). We also wipe out
# database related environment variables.
ENV.keys
  .select { |key| key.end_with?('_TOKEN') || key.start_with?('DATABASE_') }
  .each { |key| ENV.delete(key) }
