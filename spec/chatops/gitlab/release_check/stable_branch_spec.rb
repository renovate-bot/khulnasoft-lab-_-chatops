# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::StableBranch do
  subject(:stable_branch) { described_class.new(client, project, version) }

  let(:client) { instance_spy(Chatops::Gitlab::Client) }
  let(:project) { 'gitlab-org/security/gitlab' }
  let(:version) { '14.2' }

  describe '#exists?' do
    it 'returns true if branch does not raise error' do
      allow(client)
        .to receive(:branch)
        .with('gitlab-org/security/gitlab', '14-2-stable-ee')

      expect(stable_branch.exists?).to eq(true)
    end

    it 'returns false if branch raises NotFound' do
      allow(client)
        .to receive(:branch)
        .with('gitlab-org/security/gitlab', '14-2-stable-ee')
        .and_raise(gitlab_error(:NotFound))

      expect(stable_branch.exists?).to eq(false)
    end

    context 'with omnibus project' do
      let(:project) { 'gitlab-org/security/omnibus-gitlab' }

      it 'returns true if branch does not raise error' do
        allow(client)
          .to receive(:branch)
          .with('gitlab-org/security/omnibus-gitlab', '14-2-stable')

        expect(stable_branch.exists?).to eq(true)
      end
    end
  end

  describe '#contains_commit?' do
    it 'returns true if branch contains commit' do
      branches_with_commit = [instance_double('branch', type: 'branch', name: '14-2-stable-ee')]

      allow(client)
        .to receive(:refs_containing_commit)
        .with(project: 'gitlab-org/security/gitlab', sha: 'sha', type: 'branch')
        .and_return(branches_with_commit)

      expect(stable_branch.contains_commit?('sha')).to eq(true)
    end

    it 'returns false if branch does not contain commit' do
      branches_with_commit = [instance_double('branch', type: 'branch', name: 'some-branch')]

      allow(client)
        .to receive(:refs_containing_commit)
        .with(project: 'gitlab-org/security/gitlab', sha: 'sha', type: 'branch')
        .and_return(branches_with_commit)

      expect(stable_branch.contains_commit?('sha')).to eq(false)
    end

    context 'with omnibus project' do
      let(:project) { 'gitlab-org/security/omnibus-gitlab' }

      it 'returns true if branch contains commit' do
        branches_with_commit = [instance_double('branch', type: 'branch', name: '14-2-stable')]

        allow(client)
          .to receive(:refs_containing_commit)
          .with(project: 'gitlab-org/security/omnibus-gitlab', sha: 'sha', type: 'branch')
          .and_return(branches_with_commit)

        expect(stable_branch.contains_commit?('sha')).to eq(true)
      end
    end
  end

  describe '#name' do
    it 'returns branch name' do
      expect(stable_branch.name).to eq('14-2-stable-ee')
    end

    context 'with omnibus project' do
      let(:project) { 'gitlab-org/security/omnibus-gitlab' }

      it 'returns branch name' do
        expect(stable_branch.name).to eq('14-2-stable')
      end
    end
  end
end
