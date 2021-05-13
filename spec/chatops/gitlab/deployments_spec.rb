# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Deployments do
  let(:client) { Chatops::Gitlab::Client.new(token: 'token').internal_client }
  let(:project) { 'gitlab-org/foo/bar' }

  def mock_latest_deployments(environment, results)
    expect(client).to receive(:latest_deployments)
      .with(project, environment, limit: 2)
      .and_return(results)
  end

  def deployment(messages)
    stub = double('Gitlab::ObjectifiedHash', messages) # rubocop:disable RSpec/VerifiedDoubles

    Chatops::Gitlab::Deployment.new(stub)
  end

  describe '#upcoming_and_current' do
    it 'returns a running and a successful deployment' do
      deployments = [
        deployment(ref: 'main', sha: 'abcdef', status: 'running'),
        deployment(ref: 'main', sha: 'aabbcc', status: 'success')
      ]

      mock_latest_deployments('gprd', deployments)

      instance = described_class.new(client, project)
      latest = instance.upcoming_and_current('gprd')

      expect(latest.size).to eq(2)
      expect(latest).to all(be_kind_of(Chatops::Gitlab::Deployment))
    end

    it 'returns a single deployment with no running deploys' do
      deployments = [
        deployment(ref: 'main', sha: 'abcdef', status: 'success'),
        deployment(ref: 'main', sha: 'aabbcc', status: 'success')
      ]

      mock_latest_deployments('gprd', deployments)

      instance = described_class.new(client, project)
      latest = instance.upcoming_and_current('gprd')

      expect(latest.size).to eq(1)
      expect(latest.first).to be_success
      expect(latest.first.sha).to eq('abcdef')
    end

    it 'removes failed deployments' do
      deployments = [
        deployment(ref: 'main', sha: 'abcdef', status: 'failed'),
        deployment(ref: 'main', sha: 'aabbcc', status: 'success')
      ]

      mock_latest_deployments('gprd', deployments)

      instance = described_class.new(client, project)
      latest = instance.upcoming_and_current('gprd')

      expect(latest.size).to eq(1)
      expect(latest.first).to be_success
      expect(latest.first.sha).to eq('aabbcc')
    end
  end
end
