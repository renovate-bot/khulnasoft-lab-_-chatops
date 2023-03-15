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

  describe '#batched_background_migrations' do
    let(:database) { 'main' }
    let(:query) { { query: { database: database } } }

    it 'returns the batched background migrations' do
      migrations = instance_double('migrations')

      expect(client.internal_client)
        .to receive(:get)
        .with('/admin/batched_background_migrations', query)
        .and_return(migrations)

      client.batched_background_migrations(database: database)
    end

    it 'sends a request to the correct url' do
      admin_api = stub_request(:get, 'https://localhost/api/v4/admin/batched_background_migrations?database=main')

      client.batched_background_migrations(database: database)

      expect(admin_api).to have_been_requested
    end
  end

  describe '#batched_background_migration' do
    let(:database) { 'main' }
    let(:query) { { query: { database: database } } }
    let(:migration) { instance_double('migration', id: 10) }

    it 'returns a batched background migration' do
      migration = instance_double('migration', id: 10)

      expect(client.internal_client)
        .to receive(:get)
        .with("/admin/batched_background_migrations/#{migration.id}", query)
        .and_return(migration)

      client.batched_background_migration(migration.id, database: database)
    end

    context 'when the migration does not exist' do
      let(:url) { '/admin/batched_background_migrations/1' }

      let(:missing_response) do
        instance_double(
          'response',
          code: 404,
          request: instance_double('request', base_uri: 'foo', path: url, query: query),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
        )
      end

      it 'returns nil' do
        allow(client.internal_client)
          .to receive(:get)
          .with(url, query)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        expect(client.batched_background_migration(1, database: database)).to be_nil
      end
    end

    it 'sends a request to the correct url' do
      admin_api = stub_request(:get, "https://localhost/api/v4/admin/batched_background_migrations/#{migration.id}?database=main")

      client.batched_background_migration(migration.id, database: database)

      expect(admin_api).to have_been_requested
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

  describe '#pause_batched_background_migration' do
    let(:database) { 'main' }
    let(:query) { { query: { database: database } } }
    let(:migration) { instance_double('migration', id: 10) }

    context 'when the migration does not exist' do
      let(:url) { '/admin/batched_background_migrations/1/pause' }

      let(:missing_response) do
        instance_double(
          'response',
          code: 404,
          request: instance_double('request', base_uri: 'foo', path: url),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
        )
      end

      it 'returns nil' do
        allow(client.internal_client)
          .to receive(:put)
          .with(url, query)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        expect(client.pause_batched_background_migration(1, database: database)).to be_nil
      end
    end

    it 'pauses a batched background migration' do
      expect(client.internal_client)
        .to receive(:put)
        .with("/admin/batched_background_migrations/#{migration.id}/pause", query)
        .and_return(migration)

      client.pause_batched_background_migration(migration.id, database: database)
    end

    it 'sends a request to the correct url' do
      admin_api = stub_request(:put, "https://localhost/api/v4/admin/batched_background_migrations/#{migration.id}/pause?database=main")

      client.pause_batched_background_migration(migration.id, database: database)

      expect(admin_api).to have_been_requested
    end
  end

  describe '#resume_batched_background_migration' do
    let(:database) { 'main' }
    let(:query) { { query: { database: database } } }
    let(:migration) { instance_double('migration', id: 10) }

    context 'when the migration does not exist' do
      let(:url) { '/admin/batched_background_migrations/1/resume' }

      let(:missing_response) do
        instance_double(
          'response',
          code: 404,
          request: instance_double('request', base_uri: 'foo', path: url),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
        )
      end

      it 'returns nil' do
        allow(client.internal_client)
          .to receive(:put)
          .with(url, query)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        expect(client.resume_batched_background_migration(1, database: database)).to be_nil
      end
    end

    it 'resumes a batched background migration' do
      expect(client.internal_client)
        .to receive(:put)
        .with("/admin/batched_background_migrations/#{migration.id}/resume", query)
        .and_return(migration)

      client.resume_batched_background_migration(migration.id, database: database)
    end

    it 'sends a request to the correct url' do
      admin_api = stub_request(:put, "https://localhost/api/v4/admin/batched_background_migrations/#{migration.id}/resume?database=main")

      client.resume_batched_background_migration(migration.id, database: database)

      expect(admin_api).to have_been_requested
    end
  end

  describe '#find_namespace' do
    it 'returns the namespace' do
      namespace = instance_double('namespace')

      expect(client.internal_client)
        .to receive(:get)
        .with('/namespaces/1234567')
        .and_return([namespace])

      expect(client.find_namespace('1234567')).to eq([namespace])
    end
  end

  describe '#set_feature' do
    it 'sets the value of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true' })

      client.set_feature('foo', 'true')
    end

    it 'sets the user of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true', user: 'myuser' })

      client.set_feature('foo', 'true', user: 'myuser')
    end

    it 'sets the feature group of a feature flag' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo', body: { value: 'true', feature_group: 'gitlab_team_members' })

      client.set_feature('foo', 'true', feature_group: 'gitlab_team_members')
    end

    it 'sets the percentage of actors rollout' do
      expect(client.internal_client)
        .to receive(:post)
        .with('/features/foo',
              body: {
                value: '42',
                key: 'percentage_of_actors'
              })

      client.set_feature('foo', '42', actors: true)
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
          .with('/broadcast_messages',
                body: { message: 'hello', target_path: 'world' })

        client.add_broadcast_message('hello', target_path: 'world')
      end
    end

    context 'with a start and end date' do
      it 'adds a broadcast message with the given start and end date' do
        expect(client.internal_client)
          .to receive(:post)
          .with(
            '/broadcast_messages',
            body: {
              message: 'hello',
              target_path: 'world',
              starts_at: 'foo',
              ends_at: 'bar'
            }
          )

        client.add_broadcast_message('hello',
                                     target_path: 'world',
                                     starts_at: 'foo',
                                     ends_at: 'bar')
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

  describe '#pipeline' do
    it 'gets a pipeline' do
      expect(client.internal_client)
        .to receive(:pipeline)
        .with('foo/bar', 123)

      client.pipeline('foo/bar', 123)
    end
  end

  describe '#refs_containing_commit' do
    it 'raises ArgumentError if type is not all, tag or branch' do
      expect { client.refs_containing_commit(project: 'gitlab-org/gitlab', sha: 'sha', type: 'invalid') }
        .to raise_error(ArgumentError, 'Invalid `type` argument')
    end

    %w[all tag branch].each do |type|
      it "calls commit_refs with #{type} argument" do
        expect(client.internal_client)
          .to receive(:commit_refs)
          .with('gitlab-org/gitlab', 'sha', hash_including(type: type))
          .and_return(instance_double('auto_paginate', auto_paginate: [{ type: 'branch', name: 'master' }]))

        result = client.refs_containing_commit(project: 'gitlab-org/gitlab', sha: 'sha', type: type)

        expect(result).to eq([{ type: 'branch', name: 'master' }])
      end
    end
  end
end
