# frozen_string_literal: true

RSpec::Matchers.define :trigger_release do |hash|
  match do |client|
    hash[:RELEASE_USER] ||= ENV['USER']

    expect(client)
      .to receive(:run_trigger)
      .with(
        described_class::TARGET_PROJECT,
        'release_trigger_token',
        described_class::TARGET_REF,
        a_hash_including(hash)
      )
  end
end
