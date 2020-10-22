# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Deploy do
  describe '.perform' do
    it 'supports a --production option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(production: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--production])
    end

    it 'supports a --canary option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(canary: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--canary])
    end

    it 'supports a --pre option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(pre: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--pre])
    end

    it 'supports a --release option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(release: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--release])
    end

    it 'supports a --allow-precheck-failure option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(allow_precheck_failure: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--allow-precheck-failure])
    end

    it 'supports a --skip-haproxy option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(skip_haproxy: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--skip-haproxy])
    end

    it 'supports a --rollback option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(%w[], a_hash_including(rollback: true), {})
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[--rollback])
    end

    describe '--ignore-production-checks option' do
      it 'defaults to false' do
        instance = instance_double('instance')

        expect(described_class)
          .to receive(:new)
          .with(%w[], a_hash_including(ignore_production_checks: 'false'), {})
          .and_return(instance)

        expect(instance)
          .to receive(:perform)

        described_class.perform
      end

      it 'supports a string option' do
        instance = instance_double('instance')
        reason = 'some reason, to bypass the checks'

        expect(described_class)
          .to receive(:new)
          .with(%w[], a_hash_including(ignore_production_checks: reason), {})
          .and_return(instance)

        expect(instance)
          .to receive(:perform)

        described_class.perform(["--ignore-production-checks=#{reason}"])
      end
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

    context 'with a valid version without the EE suffix' do
      it 'automatically adds the suffix' do
        command = described_class.new(%w[11.3.0])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-ee.0')

        command.perform
      end
    end

    context 'with a valid RC version' do
      it 'automatically adds the suffix' do
        command = described_class.new(%w[11.3.0-rc1])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-rc1.ee.0')

        command.perform
      end
    end

    context 'with a valid stable version' do
      it 'deploys from the stable repository' do
        command = described_class.new(%w[11.3.0-ee.0])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-ee.0')

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

    context 'with a valid auto-deploy version' do
      it 'deploys using an auto-deploy version' do
        command = described_class
          .new(%w[12.0.201906051128-30e31e4afb1.bd6aadb8c50])

        expect(command)
          .to receive(:schedule_deploy)
          .with('12.0.201906051128-30e31e4afb1.bd6aadb8c50')

        command.perform
      end
    end

    context 'with extraneous arguments' do
      it 'returns an error' do
        command = described_class
          .new(%w[12.0.201906051128-30e31e4afb1.bd6aadb8c50 --invalid-argument])

        result = command.perform

        expect(result).to include('Unprocessed arguments')
      end
    end
  end

  describe '#prepare_version' do
    context 'with a release candidate version' do
      it 'automatically adds the RC suffix if necessary' do
        command = described_class.new
        version = command.prepare_version('1.2.3-rc0')

        expect(version).to eq('1.2.3-rc0.ee.0')
      end

      it 'does not add the RC suffix if not necessary' do
        command = described_class.new
        version = command.prepare_version('1.2.3-rc0.ee.0')

        expect(version).to eq('1.2.3-rc0.ee.0')
      end
    end

    context 'with a regular version' do
      it 'automatically adds the version suffix if necessary' do
        command = described_class.new
        version = command.prepare_version('1.2.3')

        expect(version).to eq('1.2.3-ee.0')
      end

      it 'does not add the version suffix if not necessary' do
        command = described_class.new
        version = command.prepare_version('1.2.3-ee.0')

        expect(version).to eq('1.2.3-ee.0')
      end
    end
  end

  describe '#schedule_deploy' do
    context 'when the request is valid' do
      it 'returns a success message' do
        command = described_class.new(
          %w[11.3.0-rc1.ee.0],
          { ignore_production_checks: 'false' },
          'TAKEOFF_TRIGGER_TOKEN' => '123',
          'TAKEOFF_TRIGGER_PROJECT' => 'foo',
          'TAKEOFF_TRIGGER_HOST' => 'example.com',
          'GITLAB_USER_NAME' => 'Alice',
          'GITLAB_USER_LOGIN' => 'alice42'
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
            'DEPLOY_REPO': 'gitlab/pre-release',
            'DEPLOY_USER': 'Alice',
            'RELEASE_MANAGER': 'alice42',
            'IGNORE_PRODUCTION_CHECKS': 'false'
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

  describe '#environment_variables_for' do
    it 'includes the DEPLOY_ENVIRONMENT variable' do
      vars = described_class.new.environment_variables_for('1.0')

      expect(vars[:DEPLOY_ENVIRONMENT]).to eq('gstg')
    end

    it 'includes the DEPLOY_VERSION variable' do
      vars = described_class.new.environment_variables_for('1.0')

      expect(vars[:DEPLOY_VERSION]).to eq('1.0')
    end

    it 'includes the DEPLOY_REPO variable' do
      vars = described_class.new.environment_variables_for('1.0')

      expect(vars[:DEPLOY_REPO]).to eq('gitlab/pre-release')
    end

    context 'when a warmup is requested' do
      it 'includes the TAKEOFF_WARMUP environment variable' do
        command = described_class.new([], { warmup: true }, {})
        vars = command.environment_variables_for('1.0')

        expect(vars[:TAKEOFF_WARMUP]).to eq('1')
      end
    end

    context 'when a warmup is not requested' do
      it 'does not include the TAKEOFF_WARMUP environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0')

        expect(vars.key?(:TAKEOFF_WARMUP)).to eq(false)
      end
    end

    context 'when skip haproxy is requested' do
      it 'includes the ANSIBLE_SKIP_TAGS environment variable' do
        command = described_class.new([], { skip_haproxy: true }, {})
        vars = command.environment_variables_for('1.0')

        expect(vars[:ANSIBLE_SKIP_TAGS]).to eq('haproxy')
      end
    end

    context 'when skip haproxy is not requested' do
      it 'does not include the ANSIBLE_SKIP_TAGS environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0')

        expect(vars.key?(:ANSIBLE_SKIP_TAGS)).to eq(false)
      end
    end

    context 'when allow failure of prechecks is requested' do
      it 'includes the PRECHECK_IGNORE_ERRORS environment variable' do
        command = described_class.new([], { allow_precheck_failure: true }, {})
        vars = command.environment_variables_for('1.0')

        expect(vars[:PRECHECK_IGNORE_ERRORS]).to eq('yes')
      end
    end

    context 'when allow failure of prechecks is not requested' do
      it 'does not include the PRECHECK_IGNORE_ERRORS environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0')

        expect(vars.key?(:PRECHECK_IGNORE_ERRORS)).to eq(false)
      end
    end

    context 'when rollback is requested' do
      it 'includes the DEPLOY_ROLLBACK environment variable' do
        command = described_class.new([], { rollback: true }, {})
        vars = command.environment_variables_for('1.0')

        expect(vars[:DEPLOY_ROLLBACK]).to eq('yes')
      end
    end

    context 'when DEPLOY_ROLLBACK is not requested' do
      it 'does not include the DEPLOY_ROLLBACK environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0')

        expect(vars.key?(:DEPLOY_ROLLBACK)).to eq(false)
      end
    end

    context 'when IGNORE_PRODUCTION_CHECKS contains reason' do
      it 'sanitizes input for safe HTML form handling' do
        provided_reason = 'some reason, to bypass the checks'
        expected_reason = 'some+reason%2C+to+bypass+the+checks'
        command = described_class.new(
          [],
          { ignore_production_checks: provided_reason },
          {}
        )
        vars = command.environment_variables_for('1.0')

        expect(vars[:IGNORE_PRODUCTION_CHECKS]).to eq(expected_reason)
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

    it 'returns pre when the --pre option is set' do
      command = described_class.new([], pre: true)

      expect(command.environment).to eq('pre')
    end

    it 'returns release when the --release option is set' do
      command = described_class.new([], release: true)

      expect(command.environment).to eq('release')
    end

    it 'returns gprd-cny when the --production and --canary options are set' do
      command = described_class.new([], production: true, canary: true)

      expect(command.environment).to eq('gprd-cny')
    end

    it 'returns gstg-cny when the --canary option is set' do
      command = described_class.new([], production: false, canary: true)

      expect(command.environment).to eq('gstg-cny')
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

  describe 'protects release environment' do
    it 'allows packaged releases to be deployed' do
      version = '13.0.1-ee.0'
      command = described_class.new([version], release: true)

      expect(command.environment).to eq('release')
      expect(command)
        .to receive(:schedule_deploy)
        .with(version)

      command.perform
    end

    it 'does not allow RCs to be deployed' do
      version = '11.3.0-rc1.ee.0'
      command = described_class.new([version], release: true)

      expect(command.environment).to eq('release')
      expect(command)
        .not_to receive(:schedule_deploy)
        .with(version)

      command.perform
    end
    it 'does not allow auto-deploys to be deployed' do
      version = '12.0.201906051128-30e31e4afb1.bd6aadb8c50'
      command = described_class.new([version], release: true)

      expect(command.environment).to eq('release')
      expect(command)
        .not_to receive(:schedule_deploy)
        .with(version)

      command.perform
    end
  end
end
