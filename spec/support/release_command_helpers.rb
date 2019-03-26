# frozen_string_literal: true

module ReleaseCommandHelpers
  def stubbed_instance(version, arguments = {})
    env = {
      'CHAT_CHANNEL' => 'channel_id',
      'GITLAB_TOKEN' => 'gitlab_token',
      'GITLAB_USER_LOGIN' => ENV['USER'],
      'RELEASE_TRIGGER_TOKEN' => 'release_trigger_token'
    }

    # TODO: Once we move all release-related commands to `release` and
    # `security` with subcommands, deprecate `subcommand` key in favor of a
    # required argument
    command = [arguments.delete(:subcommand), version].compact

    described_class.new(command, arguments, env).tap do |instance|
      # Default to the happy path
      allow(instance).to receive(:chatops_job?).and_return(true)
    end
  end
end

RSpec.configure do |c|
  c.include ReleaseCommandHelpers, :release_command
end
