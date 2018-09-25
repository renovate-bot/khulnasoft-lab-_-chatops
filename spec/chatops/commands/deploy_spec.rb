# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Deploy do
  describe '.perform' do
    it 'supports a --production option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], { production: true }, {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--production])
    end
  end

  describe '#perform' do
    context 'without a version' do
      it 'returns an error message' do
        expect(described_class.new.perform)
          .to eq('The first argument must be the version to deploy')
      end
    end

    context 'with an invalid version' do
      it 'returns an error message' do
        expect(described_class.new(%w[11.0]).perform)
          .to match(/The specified version is invalid/)
      end
    end

    context 'with a valid stable version' do
      it 'deploys from the stable repository' do
        command = described_class.new(%w[11.3.0.ee.0])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0.ee.0')

        command.perform
      end
    end

    context 'with a valid RC version' do
      it 'deploys from the pre-release repository' do
        command = described_class.new(%w[11.3.0-rc1.ee.0])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-rc1.ee.0')

        command.perform
      end
    end
  end

  describe '#schedule_deploy' do
    context 'when the request is valid' do
      it 'returns a success message' do
        command = described_class.new(
          %w[11.3.0-rc1.ee.0],
          {},
          'TAKEOFF_TRIGGER_TOKEN' => '123',
          'TAKEOFF_TRIGGER_PROJECT' => 'foo',
          'TAKEOFF_TRIGGER_HOST' => 'example.com'
        )

        response = instance_double('response', web_url: 'bar')

        expect(command.client)
          .to receive(:run_trigger)
          .with(
            'foo',
            '123',
            :master,
            'DEPLOY_ENVIRONMENT': 'gstg',
            'DEPLOY_VERSION': '11.3.0-rc1.ee.0',
            'DEPLOY_REPO': 'gitlab/pre-release'
          )
          .and_return(response)

        message = command
          .schedule_deploy('11.3.0-rc1.ee.0')

        expect(message)
          .to eq('The deploy has been scheduled and can be viewed <bar|here>')
      end
    end

    context 'when the request is invalid' do
      it 'returns an error message' do
        command = described_class.new(
          %w[11.3.0-rc1.ee.0],
          {},
          'TAKEOFF_TRIGGER_TOKEN' => '123',
          'TAKEOFF_TRIGGER_PROJECT' => 'foo',
          'TAKEOFF_TRIGGER_HOST' => 'example.com'
        )

        expect(command.client)
          .to receive(:run_trigger)
          .and_raise(StandardError.new('oops'))

        message = command
          .schedule_deploy('11.3.0-rc1.ee.0')

        expect(message)
          .to eq('The deploy could not be scheduled: oops')
      end
    end
  end

  describe '#repository' do
    context 'when the TAKEOFF_DEPLOY_REPO variable is not specified' do
      it 'returns the defaut repository value' do
        command = described_class.new

        expect(command.repository).to eq(described_class::DEFAULT_REPO)
      end
    end

    context 'when the TAKEOFF_DEPLOY_REPO variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class.new([], {}, 'TAKEOFF_DEPLOY_REPO' => 'foo')

        expect(command.repository).to eq('foo')
      end
    end
  end

  describe '#trigger_token' do
    context 'when the TAKEOFF_TRIGGER_TOKEN variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the TAKEOFF_TRIGGER_TOKEN variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class.new([], {}, 'TAKEOFF_TRIGGER_TOKEN' => 'foo')

        expect(command.trigger_token).to eq('foo')
      end
    end
  end

  describe '#trigger_project' do
    context 'when the TAKEOFF_TRIGGER_PROJECT variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the TAKEOFF_TRIGGER_PROJECT variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class
          .new([], {}, 'TAKEOFF_TRIGGER_PROJECT' => 'foo')

        expect(command.trigger_project).to eq('foo')
      end
    end
  end

  describe '#trigger_host' do
    context 'when the TAKEOFF_TRIGGER_HOST variable is not specified' do
      it 'raises KeyError' do
        expect { described_class.new.trigger_host }.to raise_error(KeyError)
      end
    end

    context 'when the TAKEOFF_TRIGGER_HOST variable is specified' do
      it 'returns the value of the environment variable' do
        command = described_class.new([], {}, 'TAKEOFF_TRIGGER_HOST' => 'foo')

        expect(command.trigger_host).to eq('foo')
      end
    end
  end

  describe '#environment' do
    it 'returns gstg by default' do
      expect(described_class.new.environment).to eq('gstg')
    end

    it 'returns gprd when the --production option is set' do
      command = described_class.new([], production: true)

      expect(command.environment).to eq('gprd')
    end
  end

  describe '#version' do
    it 'returns the version' do
      command = described_class.new(%w[foo])

      expect(command.version).to eq('foo')
    end
  end

  describe 'version?' do
    it 'returns true if a version is given' do
      command = described_class.new(%w[foo])

      expect(command.version?).to eq(true)
    end

    it 'returns false when the version is empty' do
      command = described_class.new([''])

      expect(command.version?).to eq(false)
    end

    it 'returns false when the version is not given' do
      command = described_class.new([])

      expect(command.version?).to eq(false)
    end
  end
end
