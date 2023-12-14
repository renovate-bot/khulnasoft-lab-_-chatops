# frozen_string_literal: true

require 'vcr'
require 'rexml/document' # Without this, we get an "uninitialized constant REXML::ParseException"

VCR.configure do |c|
  c.cassette_library_dir = File.expand_path('../fixtures', __dir__)
  c.default_cassette_options = { record: :new_episodes }
  c.hook_into :webmock

  # Filter all `*_TOKEN` environment variables
  ENV.each_pair do |key, val|
    next unless key.to_s.downcase.end_with?('_token')

    c.filter_sensitive_data("[#{key}]") { val }
  end
end
