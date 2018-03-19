# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Database::ReadOnlyConnection do
  around do |example|
    if ENV['TEST_DATABASE_HOST']
      example.run
    else
      skip('There is no PostgreSQL database available')
    end
  end

  let(:connection) do
    described_class.new(
      host: ENV['TEST_DATABASE_HOST'] || 'localhost',
      port: ENV['TEST_DATABASE_PORT'] || 5432,
      user: ENV['TEST_DATABASE_USER'],
      password: ENV['TEST_DATABASE_PASSWORD'],
      database: ENV['TEST_DATABASE_NAME']
    )
  end

  describe '.from_environment' do
    it 'returns a read-only database connection' do
      env = {
        'DATABASE_HOST' => 'foo',
        'DATABASE_PORT' => 1234,
        'DATABASE_USER' => 'admin',
        'DATABASE_PASSWORD' => 'hunter2',
        'DATABASE_NAME' => 'gitlab'
      }

      expect(described_class).to receive(:new).with(
        host: 'foo',
        port: 1234,
        user: 'admin',
        password: 'hunter2',
        database: 'gitlab'
      )

      described_class.from_environment(env)
    end
  end

  describe '#execute' do
    it 'executes a read-only query' do
      result = connection.execute('SELECT 1 AS number')

      expect(result.first['number']).to eq('1')
    end

    it 'raises when trying to perform a write operation' do
      expect { connection.execute('CREATE TABLE foo ();') }
        .to raise_error(PG::ReadOnlySqlTransaction)
    end
  end
end
