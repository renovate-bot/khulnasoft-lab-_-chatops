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
    context 'without a username' do
      it 'returns an error message' do
        command = described_class.new(%w[find])

        expect(command.find).to eq('You must specify a username or email.')
      end
    end

    context 'with a valid username' do
      it 'submits the details of the user to Slack' do
        client = instance_double('client')
        user = instance_double('user')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)

        command = described_class
          .new(%w[find alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command)
          .to receive(:submit_user_details)
          .with(user)

        command.find('alice')
      end
    end

    context 'with a valid email' do
      it 'submits the details of the user to Slack' do
        client = instance_double('client')
        user = instance_double('user')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_user)
          .with('alice@gitlab.com')
          .and_return(user)

        command = described_class
          .new(%w[find alice], {}, 'GITLAB_TOKEN' => '123')

        expect(command)
          .to receive(:submit_user_details)
          .with(user)

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

  describe '#submit_user_details' do
    it 'submits the user details to Slack' do
      user = instance_double(
        'user',
        id: 123,
        avatar_url: 'http://example.com',
        name: 'Alice',
        web_url: 'http://example.com',
        bio: 'This is the bio of alice',
        state: 'active',
        email: 'alice@example.com',
        two_factor_enabled: true,
        created_at: Time.now.iso8601,
        last_activity_on: Time.now.iso8601,
        current_sign_in_at: Time.now.iso8601,
        projects_limit: 5,
        shared_runners_minutes_limit: 10
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

      command.submit_user_details(user)
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
