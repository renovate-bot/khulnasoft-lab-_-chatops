# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Explain do
  describe '.perform' do
    it 'supports a --visual option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[SELECT 1], { visual: true, without_analyze: false }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[SELECT 1 --visual])
    end
  end

  describe '#perform' do
    context 'when using a query that is clearly too dangerous to run' do
      it 'raises UnsafeQueryError' do
        command = described_class.new(%w[DROP DATABASE gitlabhq_production])

        expect { command.perform }
          .to raise_error(described_class::UnsafeQueryError)
      end
    end

    context 'when using a query that is safe to execute' do
      it 'obtains the query plan' do
        command = described_class.new(%w[SELECT 1])

        expect(command)
          .to receive(:upload_explain_plan_for)
          .with('SELECT 1')

        command.perform
      end
    end

    context 'when using a URL as the input' do
      it 'downloads and executes the plan located at the URL' do
        command = described_class.new(%w[http://example.com])

        expect(command)
          .to receive(:download_query)
          .with('http://example.com')
          .and_return('SELECT 1')

        expect(command)
          .to receive(:upload_explain_plan_for)
          .with('SELECT 1')

        command.perform
      end
    end
  end

  describe '#upload_explain_plan_for' do
    let(:command) { described_class.new(%w[SELECT 1]) }
    let(:connection) { instance_double('connection') }

    before do
      allow(command)
        .to receive(:database_connection)
        .and_return(connection)

      allow(connection)
        .to receive(:execute)
        .with('EXPLAIN (ANALYZE, BUFFERS) SELECT 1')
        .and_return([{ 'QUERY PLAN' => 'Foo' }, { 'QUERY PLAN' => 'Bar' }])
    end

    it 'obtains the EXPLAIN plan of a query' do
      expect(command)
        .to receive(:upload_plan)
        .with("Foo\nBar", nil)

      command.upload_explain_plan_for('SELECT 1')
    end

    it 'visualises the query plan when the :visual option is set' do
      command.options[:visual] = true

      expect(command)
        .to receive(:url_for_visualised_plan)
        .with("Foo\nBar")
        .and_return('http://example.com')

      expect(command)
        .to receive(:upload_plan)
        .with("Foo\nBar", 'http://example.com')

      command.upload_explain_plan_for('SELECT 1')
    end
  end

  describe '#url_for_visualised_plan' do
    let(:command) { described_class.new(%w[SELECT 1]) }

    context 'when the service responds with a 302' do
      it 'returns the URL of the query plan' do
        response = instance_double(
          'HTTP response',
          status: 302,
          headers: { 'Location' => '/foo' }
        )

        expect(HTTP)
          .to receive(:post)
          .with(described_class::EXPLAIN_HOST, form: { plan: 'Foo' })
          .and_return(response)

        expect(command.url_for_visualised_plan('Foo'))
          .to eq(described_class::EXPLAIN_HOST + '/foo')
      end
    end

    context 'when the service responds with an error' do
      it 'raises QueryVisualisationError' do
        response = instance_double('HTTP response', status: 404)

        expect(HTTP)
          .to receive(:post)
          .with(described_class::EXPLAIN_HOST, form: { plan: 'Foo' })
          .and_return(response)

        expect { command.url_for_visualised_plan('Foo') }
          .to raise_error(described_class::QueryVisualisationError)
      end
    end
  end

  describe '#database_connection' do
    it 'returns a new database connection' do
      expect(Chatops::Database::ReadOnlyConnection)
        .to receive(:new)
        .with(
          host: 'hostname',
          port: 1234,
          user: 'alice',
          password: 'hunter2',
          database: 'database'
        )

      command = described_class.new(
        [],
        {},
        'DATABASE_HOST' => 'hostname',
        'DATABASE_PORT' => 1234,
        'DATABASE_USER' => 'alice',
        'DATABASE_PASSWORD' => 'hunter2',
        'DATABASE_NAME' => 'database'
      )

      command.database_connection
    end
  end

  describe '#upload_plan' do
    let(:command) do
      described_class
        .new([], {}, 'SLACK_TOKEN' => '123', 'CHAT_CHANNEL' => '456')
    end

    context 'with a URL' do
      it 'uploads the plan to Slack' do
        upload = instance_double('upload')

        expect(Chatops::Slack::FileUpload)
          .to receive(:new)
          .with(
            file: 'foo',
            type: :text,
            channel: '456',
            token: '123',
            title: 'EXPLAIN output',
            comment: 'A visual representation of the plan can be found ' \
              '<http://example.com|here>.'
          )
          .and_return(upload)

        expect(upload).to receive(:upload)

        command.upload_plan('foo', 'http://example.com')
      end
    end

    context 'without a URL' do
      it 'uploads the plan to Slack' do
        upload = instance_double('upload')

        expect(Chatops::Slack::FileUpload)
          .to receive(:new)
          .with(
            file: 'foo',
            type: :text,
            channel: '456',
            token: '123',
            title: 'EXPLAIN output',
            comment: nil
          )
          .and_return(upload)

        expect(upload).to receive(:upload)

        command.upload_plan('foo')
      end
    end
  end

  describe '#download_query' do
    it 'downloads a query from a URL' do
      command = described_class.new

      response = instance_double('response', body: 'hello')

      expect(HTTP)
        .to receive(:get)
        .with('http://example.com')
        .and_return(response)

      expect(command.download_query('http://example.com')).to eq('hello')
    end
  end

  describe '#clearly_dangerous?' do
    it 'returns true for a query that is too dangerous to run' do
      command = described_class.new(%w[SELECT 1])

      expect(command.clearly_dangerous?('DROP TABLE foo')).to eq(true)
    end

    it 'returns true when trying to create a table' do
      command = described_class.new

      expect(command.clearly_dangerous?('CREATE TABLE foo')).to eq(true)
    end

    it 'returns false for a query that is safe to run' do
      command = described_class.new(%w[SELECT 1])

      expect(command.clearly_dangerous?('SELECT 1')).to eq(false)
    end
  end

  describe '#explain' do
    context 'when the --without-analyze option is specified' do
      it 'runs a regular EXPLAIN' do
        command = described_class.new(%w[SELECT 1], { without_analyze: true })
        connection = instance_double('connection')

        expect(command)
          .to receive(:database_connection)
          .and_return(connection)

        expect(connection)
          .to receive(:execute)
          .with('EXPLAIN SELECT 1')

        command.explain('SELECT 1')
      end
    end

    context 'when the --without-analyze option is not specified' do
      it 'runs an EXPLAIN ANALYZE' do
        command = described_class.new(%w[SELECT 1], { without_analyze: false })
        connection = instance_double('connection')

        expect(command)
          .to receive(:database_connection)
          .and_return(connection)

        expect(connection)
          .to receive(:execute)
          .with('EXPLAIN (ANALYZE, BUFFERS) SELECT 1')

        command.explain('SELECT 1')
      end
    end

  end
end
