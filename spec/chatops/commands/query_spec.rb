# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Query do
  describe '.perform' do
    it 'supports a --host option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[123], { host: 'foo' }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[123 --host foo])
    end
  end

  describe '#perform' do
    context 'when no query ID is given' do
      it 'returns an error message' do
        expect(described_class.new.perform)
          .to eq('You must specify a query ID.')
      end
    end

    context 'when the query ID is invalid' do
      it 'returns an error message' do
        expect(described_class.new(%w[foo]).perform)
          .to eq('You must specify a numerical value as the query ID.')
      end
    end

    context 'when no query exists for the given query ID' do
      it 'returns an error message' do
        command = described_class.new(%w[123])
        connection = instance_double('connection')

        expect(command)
          .to receive(:database_connection)
          .and_return(connection)

        expect(connection)
          .to receive(:execute)
          .with(/FROM pg_stat_statements.+WHERE queryid = 123/m)
          .and_return([])

        expect(command.perform)
          .to eq('No query exists for the given ID.')
      end
    end

    context 'when the query ID is valid' do
      it 'submits the query data to Slack' do
        command = described_class.new(%w[123])
        connection = instance_double('connection')
        row = { 'queryid' => 123 }

        expect(command)
          .to receive(:database_connection)
          .and_return(connection)

        expect(connection)
          .to receive(:execute)
          .and_return([row])

        expect(command)
          .to receive(:upload_query_to_slack)
          .with(row)

        expect(command)
          .to receive(:submit_query_statistics)
          .with(row)

        command.perform
      end
    end
  end

  describe '#valid_query_id?' do
    let(:command) { described_class.new }

    it 'returns true for a valid query ID' do
      expect(command.valid_query_id?('123')).to eq(true)
    end

    it 'returns false for an invalid query ID' do
      expect(command.valid_query_id?('foo')).to eq(false)
    end

    # This test exists to ensure the anchoring of the regular expression is done
    # properly.
    it 'returns false for an ID starting with text and ending with a number' do
      expect(command.valid_query_id?('foo123')).to eq(false)
    end
  end

  describe '#upload_query_to_slack' do
    it 'uploads a SQL query to Slack' do
      command = described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => 'foo')

      row = { 'queryid' => 42, 'query' => 'SELECT 1' }
      uploader = instance_double('uploader')

      expect(Chatops::Slack::FileUpload)
        .to receive(:new)
        .with(
          file: 'SELECT 1',
          type: :sql,
          channel: 'foo',
          token: '123',
          title: 'SQL for query 42'
        )
        .and_return(uploader)

      expect(uploader).to receive(:upload)

      command.upload_query_to_slack(row)
    end
  end

  describe '#submit_query_statistics' do
    it 'submits the query statistics to Slack' do
      command = described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => 'foo')

      row = {
        'queryid' => 42,
        'mean_time' => 0.5,
        'calls' => 4,
        'query' => 'SELECT 1'
      }

      message = instance_double('message')

      expect(Chatops::Slack::Message)
        .to receive(:new)
        .with(token: '123', channel: 'foo')
        .and_return(message)

      expect(message)
        .to receive(:send)
        .with(
          text: 'Query statistics for query 42:',
          attachments: an_instance_of(Array)
        )

      command.submit_query_statistics(row)
    end
  end

  describe '#attachment_fields' do
    it 'returns an Array of Slack attachment fields' do
      command = described_class.new
      row = { 'mean_time' => 0.5, 'calls' => 4, 'query' => 'SELECT 1' }
      fields = command.attachment_fields(row)

      expect(fields.length).to eq(2)

      expect(fields)
        .to include(title: 'mean_time', value: '0.5 ms', short: true)

      expect(fields)
        .to include(title: 'calls', value: 4, short: true)
    end

    it 'does not include a field for the SQL query' do
      command = described_class.new
      row = { 'query' => 'SELECT 1' }
      fields = command.attachment_fields(row)

      expect(fields).to be_empty
    end
  end

  describe '#database_connection' do
    it 'returns a read-only database connection' do
      command = described_class.new

      expect(Chatops::Database::ReadOnlyConnection)
        .to receive(:from_environment)
        .with(an_instance_of(Hash))

      command.database_connection
    end
  end

  describe '#database_environment_variables' do
    context 'without the --host option' do
      it 'returns the default environment variables' do
        command = described_class.new([], {}, 'DATABASE_PORT' => '123')

        expect(command.database_environment_variables)
          .to eq('DATABASE_PORT' => '123')
      end
    end

    context 'with the --host option' do
      it 'returns the environment variables including the custom hostname' do
        command = described_class
          .new([], { host: 'foo' }, 'DATABASE_PORT' => '123')

        expect(command.database_environment_variables)
          .to eq('DATABASE_PORT' => '123', 'DATABASE_HOST' => 'foo')
      end
    end
  end
end
