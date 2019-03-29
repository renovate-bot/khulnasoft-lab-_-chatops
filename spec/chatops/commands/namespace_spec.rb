# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Namespace do
  describe '#perform' do
    context 'without a namespace id' do
      it 'returns an error message' do
        command = described_class.new(%w[])

        expect(command.perform).to eq('You must supply a namespace ID to look up.')
      end
    end

    context 'when passed a namespace ID' do
      it 'tries to look it up' do
        command = described_class.new(%w[1234567], {}, 'GITLAB_TOKEN' => '123')

        expect(command.perform)
          .to receive(:find)
          .with('1234567')

        command.perform
      end
    end
  end
end
