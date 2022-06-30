# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Deploy do
  describe '#assert_intent!' do
    it 'returns if our intent does match current state' do
      command = described_class.new(%w[lock foo-environment])
      client = stub_const('Chatops::Chef::Client', spy)

      allow(client)
        .to receive(:environment_unlocked?)
        .and_return(true)

      expect do
        command.assert_intent!('foo-environment', 'lock')
      end.not_to raise_error
    end

    it 'raises if our intent is the same as current state' do
      command = described_class.new(%w[unlock foo-environment])
      client = stub_const('Chatops::Chef::Client', spy)

      allow(client)
        .to receive(:environment_unlocked?)
        .and_return(false)

      expect do
        command.assert_intent!('foo-environment', 'lock')
      end.to raise_error(SystemExit)
    end
  end

  describe '.perform' do
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
    it 'falls back to default behavior without a subcommand' do
      instance = described_class.new(%w[foo])

      expect(instance).to receive(:deploy)

      instance.perform
    end

    it 'runs a subcommand' do
      instance = described_class.new(%w[lock foo-environment])

      expect(instance).to receive(:lock).with('foo-environment')

      instance.perform
    end
  end

  describe '#deploy' do
    context 'without a version' do
      it 'returns an error message' do
        expect(described_class.new.perform)
          .to eq('Must provide a version and a target environment')
      end
    end

    context 'with an invalid version' do
      it 'returns an error message' do
        expect(described_class.new(%w[11.0 gstg]).perform)
          .to match(/The specified version is invalid/)
      end
    end

    context 'with a valid version without the EE suffix' do
      it 'automatically adds the suffix' do
        command = described_class.new(%w[11.3.0 gprd])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-ee.0', 'gprd')

        command.perform
      end
    end

    context 'with a valid environment and then a version' do
      it 'deploys the specified version to the specified environment' do
        command = described_class
          .new(%w[gprd 12.0.201906051128-30e31e4afb1.bd6aadb8c50])

        expect(command)
          .to receive(:schedule_deploy)
          .with('12.0.201906051128-30e31e4afb1.bd6aadb8c50', 'gprd')

        command.perform
      end
    end

    context 'with a valid version and an invalid environment' do
      it 'raises an error' do
        command = described_class
          .new(%w[imagination-land 12.0.201906051128-30e31e4afb1.bd6aadb8c50])

        expect { command.perform }.to raise_error(/Invalid environment/)
      end
    end

    context 'with a valid RC version' do
      it 'automatically adds the suffix' do
        command = described_class.new(%w[gstg-cny 11.3.0-rc1])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-rc1.ee.0', 'gstg-cny')

        command.perform
      end
    end

    context 'with a valid stable version' do
      it 'deploys from the stable repository' do
        command = described_class.new(%w[gstg-ref 11.3.0-ee.0])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-ee.0', 'gstg-ref')

        command.perform
      end
    end

    context 'with a valid RC version' do
      it 'deploys from the pre-release repository' do
        command = described_class.new(%w[11.3.0-rc1.ee.0 gprd-cny])

        expect(command)
          .to receive(:schedule_deploy)
          .with('11.3.0-rc1.ee.0', 'gprd-cny')

        command.perform
      end
    end

    context 'with a valid auto-deploy version' do
      it 'deploys using an auto-deploy version' do
        command = described_class
          .new(%w[12.0.201906051128-30e31e4afb1.bd6aadb8c50 pre])

        expect(command)
          .to receive(:schedule_deploy)
          .with('12.0.201906051128-30e31e4afb1.bd6aadb8c50', 'pre')

        command.perform
      end
    end

    context 'with a rollback' do
      it 'increments the rollbacks counter metric' do
        env = instance_double('Hash', fetch: '', "[]": '')
        allow(env).to receive(:to_hash).and_return(env)

        command = described_class
          .new(%w[12.0.201906051128-30e31e4afb1.bd6aadb8c50 gstg],
               { rollback: true },
               env)

        response = instance_double('response', web_url: 'bar')
        expect(command.client)
          .to receive(:run_trigger)
          .and_return(response)

        expect(command).to receive(:inc_rollbacks_metric)

        command.perform
      end
    end

    context 'with extraneous arguments' do
      it 'returns an error' do
        command = described_class
          .new(%w[gstg 12.0.201906051128-30e31e4afb1.bd6aadb8c50 --invalid-argument])

        result = command.perform

        expect(result).to include('Unprocessed arguments')
      end
    end
  end

  describe '#lock' do
    it 'validates the environment' do
      instance = described_class.new(%w[lock foo-environment])

      expect { instance.perform }.to raise_error(/Invalid environment/)
    end

    it 'normalizes the release environment' do
      instance = described_class.new(%w[lock release])
      client = stub_const('Chatops::Chef::Client', spy)

      instance.perform

      expect(client).to have_received(:lock_environment).with('release-gitlab')
    end

    it 'locks the given environment' do
      instance = described_class.new(%w[lock gprd])
      client = stub_const('Chatops::Chef::Client', spy)

      instance.perform

      expect(client).to have_received(:lock_environment).with('gprd')
    end
  end

  describe '#unlock' do
    it 'validates the environment' do
      instance = described_class.new(%w[unlock foo-environment])

      expect { instance.perform }.to raise_error(/Invalid environment/)
    end

    it 'normalizes the release environment' do
      instance = described_class.new(%w[unlock release])
      client = stub_const('Chatops::Chef::Client', spy)

      allow(client)
        .to receive(:environment_unlocked?)
        .and_return(false)

      instance.perform

      expect(client).to have_received(:unlock_environment).with('release-gitlab')
    end

    it 'unlocks the given environment' do
      instance = described_class.new(%w[unlock gprd])
      client = stub_const('Chatops::Chef::Client', spy)

      allow(client)
        .to receive(:environment_unlocked?)
        .and_return(false)

      instance.perform

      expect(client).to have_received(:unlock_environment).with('gprd')
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
          %w[11.3.0-rc1.ee.0 gstg],
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

        message = command.perform

        expect(message)
          .to eq('The deploy has been scheduled and can be viewed <bar|here>')
      end
    end

    context 'when the request is invalid' do
      it 'returns an error message' do
        command = described_class.new(
          %w[11.3.0-rc1.ee.0 gprd-cny],
          {},
          'TAKEOFF_TRIGGER_TOKEN' => '123',
          'TAKEOFF_TRIGGER_PROJECT' => 'foo',
          'TAKEOFF_TRIGGER_HOST' => 'example.com'
        )

        expect(command.client)
          .to receive(:run_trigger)
          .and_raise(StandardError.new('oops'))

        message = command.perform

        expect(message)
          .to eq('The deploy could not be scheduled: oops')
      end
    end
  end

  describe '#environment_variables_for' do
    it 'includes the DEPLOY_ENVIRONMENT variable' do
      vars = described_class.new.environment_variables_for('1.0', 'gstg')

      expect(vars[:DEPLOY_ENVIRONMENT]).to eq('gstg')
    end

    it 'includes the DEPLOY_VERSION variable' do
      vars = described_class.new.environment_variables_for('1.0', 'foo')

      expect(vars[:DEPLOY_VERSION]).to eq('1.0')
    end

    it 'includes the DEPLOY_REPO variable' do
      vars = described_class.new.environment_variables_for('1.0', 'foo')

      expect(vars[:DEPLOY_REPO]).to eq('gitlab/pre-release')
    end

    context 'when a warmup is requested' do
      it 'includes the TAKEOFF_WARMUP environment variable' do
        command = described_class.new([], { warmup: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:TAKEOFF_WARMUP]).to eq('1')
      end
    end

    context 'when a warmup is not requested' do
      it 'does not include the TAKEOFF_WARMUP environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars.key?(:TAKEOFF_WARMUP)).to eq(false)
      end
    end

    context 'when checkmode is requested' do
      it 'includes the CHECKMODE environment variable' do
        command = described_class.new([], { check: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:CHECKMODE]).to eq('true')
      end
    end

    context 'when skip haproxy is requested' do
      it 'includes the ANSIBLE_SKIP_TAGS environment variable' do
        command = described_class.new([], { skip_haproxy: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:ANSIBLE_SKIP_TAGS]).to eq('haproxy')
      end
    end

    context 'when skip haproxy is not requested' do
      it 'does not include the ANSIBLE_SKIP_TAGS environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars.key?(:ANSIBLE_SKIP_TAGS)).to eq(false)
      end
    end

    context 'when allow failure of prechecks is requested' do
      it 'includes the PRECHECK_IGNORE_ERRORS environment variable' do
        command = described_class.new([], { allow_precheck_failure: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:PRECHECK_IGNORE_ERRORS]).to eq('yes')
      end
    end

    context 'when allow failure of prechecks is not requested' do
      it 'does not include the PRECHECK_IGNORE_ERRORS environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars.key?(:PRECHECK_IGNORE_ERRORS)).to eq(false)
      end
    end

    context 'when rollback is requested' do
      it 'includes the DEPLOY_ROLLBACK environment variable' do
        command = described_class.new([], { rollback: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:DEPLOY_ROLLBACK]).to eq('true')
      end

      it 'includes the IGNORE_PRODUCTION_CHECKS environment variable' do
        command = described_class.new([], { rollback: true }, {})
        vars = command.environment_variables_for('1.0', 'foo')

        expect(vars[:IGNORE_PRODUCTION_CHECKS]).to include('rollback')
      end
    end

    context 'when DEPLOY_ROLLBACK is not requested' do
      it 'does not include the DEPLOY_ROLLBACK environment variable' do
        command = described_class.new
        vars = command.environment_variables_for('1.0', 'foo')

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
        vars = command.environment_variables_for('1.0', 'foo')

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

  describe 'protects release environment' do
    it 'allows packaged releases to be deployed' do
      version = '13.0.1-ee.0'
      command = described_class.new(['release', version])

      expect(command).to receive(:schedule_deploy).with(version, 'release')

      command.perform
    end

    it 'does not allow RCs to be deployed' do
      version = '11.3.0-rc1.ee.0'
      command = described_class.new(['release', version])

      expect(command).not_to receive(:schedule_deploy)

      command.perform
    end

    it 'does not allow auto-deploys to be deployed' do
      version = '12.0.201906051128-30e31e4afb1.bd6aadb8c50'
      command = described_class.new(['release', version])

      expect(command).not_to receive(:schedule_deploy)

      command.perform
    end
  end

  describe '#inc_rollbacks_metric' do
    subject(:command) do
      described_class.new(
        %w[gstg-cny 12.0.201906051128-30e31e4afb1.bd6aadb8c50],
        {},
        'DELIVERY_METRICS_TOKEN' => token,
        'DELIVERY_METRICS_URL' => url
      )
    end

    let(:token) { 'a-token' }
    let(:url) { 'http://example.com' }

    it 'sets X-Private-Token header' do
      expect(HTTP).to receive(:headers)
        .with("X-Private-Token": token)
        .and_return(instance_spy('HTTP::Client'))

      command.inc_rollbacks_metric('foo')
    end

    it 'makes a POST requests' do
      client = instance_spy('HTTP::Client')
      expect(HTTP).to receive(:headers).and_return(client)

      command.inc_rollbacks_metric('gstg-cny')

      expect(client).to have_received(:post)
        .with("#{url}/api/deployment_rollbacks_started_total/inc",
              form: { labels: 'gstg-cny' })
    end
  end
end
