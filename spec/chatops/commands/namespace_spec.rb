# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Namespace do
  describe '#perform' do
    context 'when passed a namespace ID' do
      it 'tries to look it up' do
        command = described_class.new(%w[1234567])

        expect(command)
          .to receive(:find)
          .with('1234567')

        command.perform
      end
    end
  end
end
