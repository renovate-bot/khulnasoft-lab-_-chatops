# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Client do
  let(:client) { described_class.new(token: '123', host: 'localhost') }

  describe '#initialize' do
    it 'sets the endpoint based on the hostname' do
      expect(client.internal_client.endpoint).to eq('https://localhost/api/v4')
    end
  end

  describe '#features' do
    it 'returns the feature flags' do
      collection = instance_double('collection')

      expect(client.internal_client)
        .to receive(:get)
        .with('/features')
        .and_return(collection)

      expect(collection)
        .to receive(:auto_paginate)

      client.features
    end
  end

  describe '#find_user' do
    context 'when a user could be found' do
      it 'returns the user' do
        user = instance_double('user')

        expect(client.internal_client)
          .to receive(:users)
          .with(username: 'alice')
          .and_return([user])

        expect(client.find_user('alice')).to eq(user)
      end
    end

    context 'when a user could not be found' do
      it 'returns nil' do
        expect(client.internal_client)
          .to receive(:users)
          .with(username: 'alice')
          .and_return([])

        expect(client.find_user('alice')).to be_nil
      end
    end
  end

  describe '#find_namespace' do
    context 'when a namespace could be found' do
      it 'returns the namespace' do
        namespace = instance_double('namespace')

        expect(client.internal_client)
          .to receive(:get)
          .with('/namespaces/1234567')
          .and_return([namespace])

        expect(client.find_namespace('1234567')).to eq([namespace])
      end
    end
  end

  describe '#set_feature' do
    it 'sets the value of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true' })

      client.set_feature('foo', 'true')
    end
  end

  describe '#delete_feature' do
    it 'removes the value of a feature flag' do
      expect(client.internal_client)
        .to receive(:delete)
        .with('/features/foo')

      client.delete_feature('foo')
    end
  end

  describe '#add_broadcast_message' do
    context 'without a start and end date' do
      it 'adds a broadcast message without an explicit start and end date' do
        expect(client.internal_client)
          .to receive(:post)
          .with('/broadcast_messages', body: { message: 'hello' })

        client.add_broadcast_message('hello')
      end
    end

    context 'with a start and end date' do
      it 'adds a broadcast message with the given start and end date' do
        expect(client.internal_client)
          .to receive(:post)
          .with(
            '/broadcast_messages',
            body: { message: 'hello', starts_at: 'foo', ends_at: 'bar' }
          )

        client.add_broadcast_message('hello', starts_at: 'foo', ends_at: 'bar')
      end
    end
  end

  describe '#block_user' do
    it 'blocks a user' do
      expect(client.internal_client)
        .to receive(:block_user)
        .with(1)

      client.block_user(1)
    end
  end

  describe '#unblock_user' do
    it 'unblocks a user' do
      expect(client.internal_client)
        .to receive(:unblock_user)
        .with(1)

      client.unblock_user(1)
    end
  end

  describe '#run_trigger' do
    it 'runs a trigger' do
      expect(client.internal_client)
        .to receive(:run_trigger)
        .with('foo/bar', 'abcdefg', 'master', foo: :bar)

      client.run_trigger('foo/bar', 'abcdefg', 'master', foo: :bar)
    end
  end

  describe '#pipeline_jobs' do
    it 'lists pipeline jobs' do
      expect(client.internal_client)
        .to receive(:pipeline_jobs)
        .with('foo/bar', 123, foo: :bar)

      client.pipeline_jobs('foo/bar', 123, foo: :bar)
    end
  end

  describe '#add_group_member' do
    it 'adds a member to the group' do
      group = instance_double('group')
      user = instance_double('user')

      expect(client.internal_client)
        .to receive(:add_group_member)
        .with(group, user, 40)

      client.add_group_member(group, user, 40)
    end
  end

  describe '#add_project_member' do
    it 'adds a member to the project' do
      project = instance_double('project')
      user = instance_double('user')

      expect(client.internal_client)
        .to receive(:add_team_member)
        .with(project, user, 40)

      client.add_project_member(project, user, 40)
    end
  end

  describe '#remove_group_member' do
    it 'removes a member to the group' do
      group = instance_double('group')
      user = instance_double('user')

      expect(client.internal_client)
        .to receive(:remove_group_member)
        .with(group, user)

      client.remove_group_member(group, user)
    end
  end

  describe '#remove_project_member' do
    it 'removes a member to the project' do
      project = instance_double('project')
      user = instance_double('user')

      expect(client.internal_client)
        .to receive(:remove_team_member)
        .with(project, user)

      client.remove_project_member(project, user)
    end
  end
end
