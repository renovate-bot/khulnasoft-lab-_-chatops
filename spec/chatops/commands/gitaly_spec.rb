# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Gitaly, :release_command do
  describe '.perform' do
    include_context 'release command #perform'

    describe '#tag' do
      let(:version) { '1.45.1' }

      it 'triggers a normal release' do
        instance = stubbed_instance('tag', version)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'release:gitaly:tag')

        instance.perform
      end

      it 'triggers a security release' do
        instance = stubbed_instance('tag', version, security: true)

        expect(instance).to receive(:validate_version!).with(version)
        expect(instance).to receive(:trigger_release)
          .with(version, 'security:gitaly:tag')

        instance.perform
      end
    end
  end
end
