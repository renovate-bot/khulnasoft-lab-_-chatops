# frozen_string_literal: true

module ReleaseCommandHelpers
  def stubbed_instance(version, arguments = {})
    env = {
      'GITLAB_TOKEN' => 'gitlab_token',
      'GITLAB_USER_LOGIN' => ENV['USER'],
      'RELEASE_TRIGGER_TOKEN' => 'release_trigger_token'
    }

    described_class.new([version], arguments, env).tap do |instance|
      # Default to the happy path
      allow(instance).to receive(:chatops_job?).and_return(true)
    end
  end
end

RSpec.configure do |c|
  c.include ReleaseCommandHelpers, :release_command
end
