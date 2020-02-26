# frozen_string_literal: true

module ReleaseCommandHelpers
  def stubbed_instance(*input)
    arguments =
      if input.last.is_a?(Hash)
        input.pop
      else
        {}
      end

    env = {
      'CHAT_CHANNEL' => 'channel_id',
      'GITLAB_OPS_TOKEN' => 'gitlab_ops_token',
      'GITLAB_USER_LOGIN' => ENV['USER'],
      'RELEASE_TRIGGER_TOKEN' => 'release_trigger_token'
    }

    described_class.new(input, arguments, env).tap do |instance|
      # Default to the happy path
      allow(instance).to receive(:chatops_job?).and_return(true)
    end
  end
end

RSpec.configure do |c|
  c.include ReleaseCommandHelpers, :release_command
end
