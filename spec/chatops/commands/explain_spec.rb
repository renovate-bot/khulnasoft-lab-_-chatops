# frozen_string_literal: true

describe Chatops::Commands::Explain do
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
          .to receive(:explain_plan_for)
          .with('SELECT 1')

        command.perform
      end
    end
  end

  describe '#explain_plan_for' do
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
      expect(command.explain_plan_for('SELECT 1'))
        .to eq("```\nFoo\nBar\n```")
    end

    it 'visualises the query plan when the :visual option is set' do
      command.options[:visual] = true

      expect(command)
        .to receive(:url_for_visualised_plan)
        .with("Foo\nBar")
        .and_return('http://example.com')

      expect(command.explain_plan_for('SELECT 1'))
        .to eq("```\nFoo\nBar\n```\n\nVisualised: http://example.com")
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

  describe '#clearly_dangerous?' do
    it 'returns true for a query that is too dangerous to run' do
      command = described_class.new(%w[SELECT 1])

      expect(command.clearly_dangerous?('DROP TABLE foo')).to eq(true)
    end

    it 'returns false for a query that is safe to run' do
      command = described_class.new(%w[SELECT 1])

      expect(command.clearly_dangerous?('SELECT 1')).to eq(false)
    end
  end
end
