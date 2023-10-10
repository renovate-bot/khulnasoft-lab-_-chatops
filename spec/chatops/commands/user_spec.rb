# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::User do
  describe '.perform' do
    it 'includes examples in the --help output' do
      output = described_class.perform(%w[--help])

      expect(output).to include('Available subcommands:')
      expect(output).to include('Examples:')
    end
  end

  describe '#perform' do
    context 'when using a valid subcommand' do
      it 'executes the subcommand' do
        command = described_class.new(%w[find alice])

        expect(command)
          .to receive(:find)
          .with('alice')

        command.perform
      end
    end

    context 'when using an invalid subcommand' do
      it 'returns an error message' do
        command = described_class.new(%w[foo])

        expect(command).to receive(:unsupported_command)

        command.perform
      end
    end
  end

  describe '.available_subcommands' do
    it 'returns a String' do
      expect(described_class.available_subcommands).to include('* find')
    end
  end

  describe '#find' do
    let(:fake_client) { spy }
    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    context 'without a username' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.find).to eq('You must specify a username or email.')
      end
    end

    context 'with a valid username' do
      let(:emails) do
        [
          Gitlab::ObjectifiedHash.new('id' => 1, 'email' => 'alice@example.com'),
          Gitlab::ObjectifiedHash.new('id' => 2, 'email' => 'alice@foo.com')
        ]
      end

      it 'submits the details of the user to Slack' do
        user = instance_double('user', id: 1)

        expect(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)

        expect(fake_client)
          .to receive(:emails)
          .with(user.id)
          .and_return(emails)

        command = described_class
          .new(%w[find alice], *env)

        expect(command)
          .to receive(:submit_user_details)
          .with(user, emails.collect(&:email))

        command.find('alice')
      end
    end

    context 'with a username and no secondary email' do
      let(:emails) { [] }

      it 'submits the details of the user to Slack' do
        user = instance_double('user', id: 1)

        expect(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)

        expect(fake_client)
          .to receive(:emails)
          .with(user.id)
          .and_return(emails)

        command = described_class
          .new(%w[find alice], *env)

        expect(command)
          .to receive(:submit_user_details)
          .with(user, emails.collect(&:email))

        command.find('alice')
      end
    end

    context 'with a valid email and a secondary email' do
      let(:emails) do
        [
          Gitlab::ObjectifiedHash.new('id' => 1, 'email' => 'alice@example.com'),
          Gitlab::ObjectifiedHash.new('id' => 2, 'email' => 'alice@foo.com')
        ]
      end

      it 'submits the details of the user to Slack' do
        user = instance_double('user', id: 1)

        expect(fake_client)
          .to receive(:find_user)
          .with('alice@gitlab.com')
          .and_return(user)

        expect(fake_client)
          .to receive(:emails)
          .with(user.id)
          .and_return(emails)

        command = described_class
          .new(%w[find alice], *env)

        expect(command)
          .to receive(:submit_user_details)
          .with(user, emails.collect(&:email))

        command.find('alice@gitlab.com')
      end
    end

    context 'with a valid email and no secondary email' do
      let(:emails) { [] }

      it 'submits the details of the user to Slack' do
        user = instance_double('user', id: 1)

        expect(fake_client)
          .to receive(:find_user)
          .with('alice@gitlab.com')
          .and_return(user)

        expect(fake_client)
          .to receive(:emails)
          .with(user.id)
          .and_return(emails)

        command = described_class
          .new(%w[find alice], *env)

        expect(command)
          .to receive(:submit_user_details)
          .with(user, emails.collect(&:email))

        command.find('alice@gitlab.com')
      end
    end

    context 'with a non-existing username' do
      it 'returns an error message' do
        client = instance_double('client')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[find alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command.find('alice'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a non-existing email' do
      it 'returns an error message' do
        client = instance_double('client')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice@gitlab.com')
          .and_return(nil)

        command = described_class
          .new(%w[find alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command.find('alice@gitlab.com'))
          .to eq('No user could be found for "alice@gitlab.com".')
      end
    end
  end

  describe '#block' do
    context 'without a username' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.block).to eq('You must specify a username to block.')
      end
    end

    context 'with an non-existing username' do
      it 'returns an error message' do
        client = instance_double('client')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[block alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command.block('alice'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a valid username' do
      let(:client) { instance_double('client') }
      let(:user) { instance_double('user', id: 1) }
      let(:command) do
        described_class.new(%w[block alice], {}, 'GITLAB_TOKEN' => '123')
      end

      before do
        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        allow(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'blocks the user' do
        expect(client)
          .to receive(:block_user)
          .with(user.id)
          .and_return(true)

        expect(command.block('alice')).to eq('The user has been blocked.')
      end

      it 'returns an error message if the user could not be blocked' do
        expect(client)
          .to receive(:block_user)
          .with(user.id)
          .and_return(false)

        expect(command.block('alice')).to eq('The user could not be blocked.')
      end
    end
  end

  describe '#unblock' do
    context 'without a username' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.unblock).to eq('You must specify a username to unblock.')
      end
    end

    context 'with an non-existing username' do
      it 'returns an error message' do
        client = instance_double('client')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[unblock alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command.unblock('alice'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a valid username' do
      let(:client) { instance_double('client') }
      let(:user) { instance_double('user', id: 1) }
      let(:command) do
        described_class.new(%w[unblock alice], {}, 'GITLAB_TOKEN' => '123')
      end

      before do
        allow(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        allow(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'unblocks the user' do
        expect(client)
          .to receive(:unblock_user)
          .with(user.id)
          .and_return(true)

        expect(command.unblock('alice')).to eq('The user has been unblocked.')
      end

      it 'returns an error message if the user could not be unblocked' do
        expect(client)
          .to receive(:unblock_user)
          .with(user.id)
          .and_return(false)

        expect(command.unblock('alice'))
          .to eq('The user could not be unblocked.')
      end
    end
  end

  describe '#update_email' do
    let(:user) { instance_double('user', id: 1, email: 'alice@example.com') }
    let(:new_email) { 'new_email@example.com' }
    let(:old_email) { 'alice@example.com' }
    let(:fake_client) { spy }
    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    context 'without a username or email' do
      it 'returns an error message' do
        command = described_class.new(%w[update_email])

        expect(command.update_email)
          .to eq('You must specify a username or email.')
      end
    end

    context 'without a new email address' do
      it 'returns an error message' do
        command = described_class.new(%w[update_email alice])

        expect(command.update_email('alice'))
          .to eq('You must specify the new email address.')
      end
    end

    context 'with a non-existing username' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[update_email alice new_email@example.com],
               *env)

        expect(command.update_email('alice', 'new_email@example.com'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a non-existing email' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(nil)

        command = described_class
          .new(%w[update_email alice@example.com new_email@example.com], *env)

        expect(command
          .update_email('alice@example.com', 'new_email@example.com'))
          .to eq('No user could be found for "alice@example.com".')
      end
    end

    context 'when an error occurs adding the new email' do
      let(:command) do
        described_class
          .new(%w[update_email alice new_email@example.com], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'returns an error message' do
        response = instance_double(
          'response',
          code: 401,
          request: instance_double('request', base_uri: 'foo', path: '/foo'),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'foo')
        )

        expect(command)
          .to receive(:add_email)
          .with(user, new_email)
          .and_raise(Gitlab::Error::ResponseError.new(response))

        expect(command
          .update_email('alice', 'new_email@example.com'))
          .to eq('Failed to update user: foo')
      end
    end

    context 'when an error occurs removing the old email' do
      let(:command) do
        described_class
          .new(%w[update_email alice new_email@example.com], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'returns an error message' do
        response = instance_double(
          'response',
          code: 401,
          request: instance_double('request', base_uri: 'foo', path: '/foo'),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'foo')
        )

        expect(command)
          .to receive(:remove_old_email)
          .with(user, old_email)
          .and_raise(Gitlab::Error::ResponseError.new(response))

        expect(command
          .update_email('alice', 'new_email@example.com'))
          .to eq('Failed to update user: foo')
      end
    end

    context 'with a valid username' do
      let(:command) do
        described_class
          .new(%w[update_email alice new_email@example.com], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'adds new email to user' do
        expect(command)
          .to receive(:validate)
          .with(new_email)
          .and_return(true)

        expect(command)
          .to receive(:add_email)
          .with(user, new_email)
          .and_return(true)

        expect(command)
          .to receive(:remove_old_email)
          .with(user, old_email)
          .and_return(true)

        expect(command)
          .to receive(:find)
          .with(new_email)

        command.update_email('alice', 'new_email@example.com')
      end
    end

    context 'with a valid email' do
      let(:command) do
        described_class
          .new(%w[update_email alice@example.com new_email@example.com], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(user)
      end

      it 'adds new email to user' do
        expect(command)
          .to receive(:validate)
          .with(new_email)
          .and_return(true)

        expect(command)
          .to receive(:add_email)
          .with(user, new_email)

        expect(command)
          .to receive(:remove_old_email)
          .with(user, old_email)

        expect(command)
          .to receive(:find)
          .with(new_email)

        command.update_email('alice@example.com', 'new_email@example.com')
      end
    end
  end

  describe '#note' do
    let(:email) { 'alice@example.com' }
    let(:user) { instance_double('user', id: 1, email: email, note: '') }
    let(:date) { Time.now.strftime('%F') }
    let(:new_note) { "#{user.note}\n#{date}: example note" }
    let(:fake_client) { spy }
    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    context 'without a username or email' do
      it 'returns an error message' do
        command = described_class.new(%w[note])

        expect(command.note)
          .to eq('You must specify a username or email.')
      end
    end

    context 'without a note to add' do
      it 'returns an error message' do
        command = described_class.new(%w[note alice])

        expect(command.note('alice'))
          .to eq('You must specify an admin note to add.')
      end
    end

    context 'with a non-existing username' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[note alice 'example note'],
               *env)

        expect(command.note('alice', 'example note'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a non-existing email' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(nil)

        command = described_class
          .new(%w[note alice@example.com 'example note'], *env)

        expect(command
          .note('alice@example.com', 'example note'))
          .to eq('No user could be found for "alice@example.com".')
      end
    end

    context 'when an error occurs adding the admin note' do
      let(:command) do
        described_class
          .new(%w[note alice 'example note'], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'returns an error message' do
        response = instance_double(
          'response',
          code: 401,
          request: instance_double('request', base_uri: 'foo', path: '/foo'),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'foo')
        )

        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, note: new_note)
          .and_raise(Gitlab::Error::ResponseError.new(response))

        expect(command
          .note('alice', 'example note'))
          .to eq('Failed to update user: foo')
      end
    end

    context 'with a valid username' do
      let(:command) do
        described_class
          .new(%w[note alice 'example note'], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'adds a new note to the user' do
        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, note: new_note)

        expect(command)
          .to receive(:find)
          .with('alice')

        command.note('alice', 'example note')
      end
    end

    context 'with a valid email' do
      let(:command) do
        described_class
          .new(%w[note alice@example.com 'example note'], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(user)
      end

      it 'adds a new note to the user' do
        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, note: new_note)

        expect(command)
          .to receive(:find)
          .with('alice@example.com')

        command.note('alice@example.com', 'example note')
      end
    end
  end

  describe '#idle' do
    let(:email) { 'alice@example.com' }
    let(:user) { instance_double('user', id: 1, username: 'alice') }
    let(:new_username) { "#{user.username}_idle" }
    let(:fake_client) { spy }
    let(:env) do
      [
        {},
        'SLACK_TOKEN' => 'token',
        'CHAT_CHANNEL' => 'channel',
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    context 'without a username or email' do
      it 'returns an error message' do
        command = described_class.new(%w[idle])

        expect(command.idle)
          .to eq('You must specify a username or email.')
      end
    end

    context 'with a non-existing username' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        command = described_class
          .new(%w[idle alice],
               *env)

        expect(command.idle('alice'))
          .to eq('No user could be found for "alice".')
      end
    end

    context 'with a non-existing email' do
      it 'returns an error message' do
        expect(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(nil)

        command = described_class
          .new(%w[idle alice@example.com], *env)

        expect(command
          .idle('alice@example.com'))
          .to eq('No user could be found for "alice@example.com".')
      end
    end

    context 'when an error occurs changing the username' do
      let(:command) do
        described_class
          .new(%w[idle alice], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'returns an error message' do
        response = instance_double(
          'response',
          code: 401,
          request: instance_double('request', base_uri: 'foo', path: '/foo'),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'foo')
        )

        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, username: new_username)
          .and_raise(Gitlab::Error::ResponseError.new(response))

        expect(command
          .idle('alice'))
          .to eq('Failed to update username: foo')
      end
    end

    context 'with a valid username' do
      let(:command) do
        described_class
          .new(%w[idle alice], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)
      end

      it 'appends _idle to the username' do
        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, username: new_username)

        expect(command)
          .to receive(:find)
          .with(new_username)

        command.idle('alice')
      end
    end

    context 'with a valid email' do
      let(:command) do
        described_class
          .new(%w[idle alice@example.com], *env)
      end

      before do
        allow(fake_client)
          .to receive(:find_user)
          .with('alice@example.com')
          .and_return(user)
      end

      it 'appends _idle to the username' do
        expect(fake_client)
          .to receive(:edit_user)
          .with(user.id, username: new_username)

        expect(command)
          .to receive(:find)
          .with(new_username)

        command.idle('alice@example.com')
      end
    end
  end

  describe '#validate' do
    context 'without a valid new email' do
      it 'returns false' do
        command = described_class
          .new(%w[update_email alice new_emailexample.com])
        email = 'new_emailexample.com'

        expect(command.validate(email)).to be false
      end
    end

    context 'with a valid new email' do
      it 'returns true' do
        command = described_class
          .new(%w[update_email alice new_email@example.com])
        email = 'new_email@example.com'

        expect(command.validate(email)).to be true
      end
    end
  end

  describe '#add_email' do
    let(:user) { instance_double('user', id: 1, email: 'alice@example.com') }
    let(:new_email) { 'new_email@example.com' }
    let(:fake_client) { spy }

    let(:env) do
      [
        {},
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    it 'adds a new email to the user' do
      command = described_class
        .new(%w[update_email alice new_email@example.com], *env)

      expect(fake_client)
        .to receive(:edit_user)
        .with(user.id, email: new_email, skip_reconfirmation: true)

      command.add_email(user, new_email)
    end
  end

  describe '#remove_old_email' do
    let(:user) { instance_double('user', id: 1, email: 'alice@example.com') }
    let(:old_email) { 'alice@example.com' }
    let(:fake_client) { spy }

    let(:env) do
      [
        {},
        'GITLAB_TOKEN' => 'token'
      ]
    end

    before do
      stub_const('Chatops::Gitlab::Client', fake_client)
    end

    secondary_emails = [
      Gitlab::ObjectifiedHash.new(
        'id' => 1, 'email' => 'alice@example.com'
      )
    ]

    it 'removes the users old primary email' do
      command = described_class
        .new(%w[update_email alice new_email@example.com], *env)

      expect(fake_client)
        .to receive(:emails)
        .with(user.id)
        .and_return(secondary_emails)

      expect(fake_client)
        .to receive(:delete_email)
        .with(secondary_emails[0].id, user.id)

      command.remove_old_email(user, old_email)
    end
  end

  describe '#submit_user_details' do
    let(:user_secondary_emails) { [] }

    it 'submits the user details to Slack' do
      user = instance_double(
        'user',
        id: 123,
        avatar_url: 'http://example.com',
        name: 'Alice',
        username: 'alice',
        web_url: 'http://example.com',
        bio: 'This is the bio of alice',
        state: 'active',
        email: 'alice@example.com',
        two_factor_enabled: true,
        created_at: Time.now.iso8601,
        confirmed_at: Time.now.iso8601,
        last_activity_on: Time.now.iso8601,
        current_sign_in_at: Time.now.iso8601,
        projects_limit: 5,
        shared_runners_minutes_limit: 10,
        note: 'Example Admin note'
      )

      command = described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => '456')

      message = instance_double('message')

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '123', channel: '456')
        .and_return(message)

      expect(message)
        .to receive(:send)
        .with(a_hash_including(attachments: an_instance_of(Array)))

      command.submit_user_details(user, user_secondary_emails)
    end
  end

  describe '#unsupported_command' do
    it 'returns an error message' do
      command = described_class.new

      expect(command.unsupported_command)
        .to match(/The provided subcommand is invalid/)
    end
  end

  describe '#two_factor_label_for_user' do
    let(:command) { described_class.new }

    it 'returns a label for a user with 2FA' do
      user = instance_double('user', two_factor_enabled: true)

      expect(command.two_factor_label_for_user(user))
        .to eq(':status_success: Enabled')
    end

    it 'returns a label for a user without 2FA' do
      user = instance_double('user', two_factor_enabled: false)

      expect(command.two_factor_label_for_user(user))
        .to eq(':status_warning: Disabled')
    end
  end

  describe '#color_for_user' do
    let(:command) { described_class.new }

    it 'returns the color for an active user' do
      user = instance_double('user', state: 'active')

      expect(command.color_for_user(user)).to eq(described_class::COLOR_ACTIVE)
    end

    it 'returns the color for a blocked user' do
      user = instance_double('user', state: 'blocked')

      expect(command.color_for_user(user)).to eq(described_class::COLOR_BLOCKED)
    end
  end
end
