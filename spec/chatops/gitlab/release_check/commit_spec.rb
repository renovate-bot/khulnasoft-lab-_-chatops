# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::Commit do
  describe '#deployed_to_gprd?' do
    subject(:deployed_to_gprd) { described_class.new(gitlab, project, sha).deployed_to_gprd? }

    let(:sha) { 'sha' }
    let(:gitlab_project) { 'gitlab-org/security/gitlab' }
    let(:gitlab) { instance_spy(Chatops::Gitlab::Client) }

    let(:gitlab_production_status) do
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
        .with(gitlab, project)
        .and_return(deployments)

      allow(deployments)
        .to receive(:upcoming_and_current)
        .with('gprd')
        .and_return([production_status])
    end

    context 'with gitlab project' do
      let(:project) { gitlab_project }
      let(:production_status) { gitlab_production_status }

      it 'returns false if commit has not been deployed to gprd' do
        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: gitlab_project, sha: sha, type: 'branch')
          .and_return([])

        expect(deployed_to_gprd).to eq(false)
      end

      it 'returns true if commit has been deployed to gprd' do
        branches_with_commit = [instance_double('branch', type: 'branch', name: gitlab_production_status.ref)]

        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: gitlab_project, sha: sha, type: 'branch')
          .and_return(branches_with_commit)

        expect(deployed_to_gprd).to eq(true)
      end
    end

    context 'with omnibus project' do
      let(:project) { omnibus_project }
      let(:omnibus_project) { 'gitlab-org/security/omnibus-gitlab' }
      let(:production_status) { omnibus_production_status }

      let(:omnibus_production_status) do
        instance_double(
          'deployment',
          role: 'gprd',
          version: '14.8.0-pre',
          revision: '0874a8d346c',
          ref: '14.8.202202220320+62b2458151c.bef3527e358',
          package: '14.8.202202220320-62b2458151c.bef3527e358',
          sha: 'long-sha',
          status: 'success',
          short_sha: '0874a8d346c'
        )
      end

      it 'returns true if commit has been deployed to gprd' do
        tags_with_commit = [instance_double('tag', type: 'tag', name: omnibus_production_status.ref)]

        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: omnibus_project, sha: sha, type: 'tag')
          .and_return(tags_with_commit)

        expect(deployed_to_gprd).to eq(true)
      end
    end
  end
end
