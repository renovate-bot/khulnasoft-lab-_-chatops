# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::StableBranch do
  subject(:stable_branch) { described_class.new(client, gitlab_ee, version) }

  let(:client) { instance_spy(Chatops::Gitlab::Client) }
  let(:gitlab_ee) { 'gitlab-org/security/gitlab' }
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
  end

  describe '#name' do
    it 'returns branch name' do
      expect(stable_branch.name).to eq('14-2-stable-ee')
    end
  end
end
