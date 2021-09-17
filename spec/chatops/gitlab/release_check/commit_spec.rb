# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::Commit do
  describe '#deployed_to_gprd?' do
    subject(:deployed_to_gprd) { described_class.new(gitlab, project, sha).deployed_to_gprd? }

    let(:sha) { 'sha' }
    let(:project) { 'gitlab-org/security/gitlab' }
    let(:gitlab) { instance_spy(Chatops::Gitlab::Client) }

    let(:production_status) do
      instance_double(
        'deployment',
        role: 'gprd',
        version: '11.9.0-pre',
        revision: '0874a8d346c',
        ref: '11-9-auto-deploy-20190804',
        package: '11.9.201908042020-0874a8d346c.2ee9f1d280d',
        sha: 'long-sha',
        status: 'success',
        short_sha: '0874a8d346c'
      )
    end

    before do
      deployments = instance_double(Chatops::Gitlab::Deployments)
      allow(Chatops::Gitlab::Deployments)
        .to receive(:new)
        .with(gitlab, 'gitlab-org/security/gitlab')
        .and_return(deployments)

      allow(deployments)
        .to receive(:upcoming_and_current)
        .with('gprd')
        .and_return([production_status])
    end

    it 'returns false if commit has not been deployed to gprd' do
      allow(gitlab)
        .to receive(:refs_containing_commit)
        .with(project: 'gitlab-org/security/gitlab', sha: sha, type: 'branch')
        .and_return([])

      expect(deployed_to_gprd).to eq(false)
    end

    it 'returns true if commit has been deployed to gprd' do
      branches_with_commit = [instance_double('branch', type: 'branch', name: production_status.ref)]

      allow(gitlab)
        .to receive(:refs_containing_commit)
        .with(project: 'gitlab-org/security/gitlab', sha: sha, type: 'branch')
        .and_return(branches_with_commit)

      expect(deployed_to_gprd).to eq(true)
    end
  end
end
