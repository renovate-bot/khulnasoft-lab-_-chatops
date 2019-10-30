# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Helm, :release_command do
  describe '.perform' do
    include_context 'release command #perform'

    describe '#tag' do
      let(:gitlab_version) { '12.1.1' }
      let(:charts_version) { '2.1.1' }

      it 'triggers a normal release' do
        instance = stubbed_instance('tag', charts_version, gitlab_version)

        expect(instance).to receive(:validate_version!).with(charts_version)
        expect(instance).to receive(:validate_version!).with(gitlab_version)
        expect(instance).to receive(:trigger_release)
          .with(gitlab_version,
                'release:helm:tag',
                'CHARTS_VERSION' => charts_version)

        instance.perform
      end
    end
  end
end
