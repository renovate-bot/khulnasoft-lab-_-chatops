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
