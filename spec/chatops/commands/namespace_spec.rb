# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Namespace do
  describe '#perform' do
    context 'without a namespace id' do
      it 'returns an error message' do
        command = described_class.new

        expect(command.perform).to eq('You must supply a namespace ID to look up.')

        command.perform
      end
    end

    context 'when passed a namespace ID' do
      it 'tries to look it up' do
        command = described_class.new(%w[1234567], {}, 'GITLAB_TOKEN' => '123')
        client = instance_double('client')
        namespace = instance_double('namespace')

        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: '123')
          .and_return(client)

        expect(client)
          .to receive(:find_namespace)
          .with('1234567')
          .and_return(namespace)

        expect(command)
          .to receive(:submit_namespace_details)
          .with(namespace)

        command.perform
      end
    end
  end
end
