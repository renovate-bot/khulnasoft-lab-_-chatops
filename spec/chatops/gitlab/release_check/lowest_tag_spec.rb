# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::LowestTag do
  describe '#execute' do
    subject(:execute) { described_class.new(gitlab, project, sha).execute }

    let(:sha) { 'sha' }
    let(:project) { 'gitlab-org/security/gitlab' }
    let(:gitlab) { instance_spy(Chatops::Gitlab::Client) }

    context 'when commit is present in gitlab tags' do
      it 'returns the lowest tag ignoring RCs' do
        tags_with_commit = [
          instance_double('tag', type: 'tag', name: 'v13.2.0-rc2-ee'),
          instance_double('tag', type: 'tag', name: 'v13.2.0-rc10-ee'),
          instance_double('tag', type: 'tag', name: 'v13.2.0-ee'),
          instance_double('tag', type: 'tag', name: 'v13.10.1-ee'),
          instance_double('tag', type: 'tag', name: 'v13.10.0-ee')
        ]

        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: project, sha: sha, type: 'tag')
          .and_return(tags_with_commit)

        expect(execute).to eq('v13.2.0-ee')
      end

      it 'does not fail with a tag that does not follow naming convention' do
        tags_with_commit = [
          instance_double('tag', type: 'tag', name: '11-10-0cfa69752d8-0d9531c80-ee'),
          instance_double('tag', type: 'tag', name: 'v14.3.0-ee')
        ]

        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: project, sha: sha, type: 'tag')
          .and_return(tags_with_commit)

        expect(execute).to eq('v14.3.0-ee')
      end
    end

    context 'when commit is present in omnibus tags' do
      subject(:execute) { described_class.new(gitlab, project, sha).execute }

      let(:project) { 'gitlab-org/security/omnibus-gitlab' }

      it 'returns the lowest tag ignoring RCs' do
        tags_with_commit = [
          instance_double('tag', type: 'tag', name: '13.2.0+rc2.ee.0'),
          instance_double('tag', type: 'tag', name: '13.2.0+rc10.ee.0'),
          instance_double('tag', type: 'tag', name: '13.2.0+ee.0'),
          instance_double('tag', type: 'tag', name: '13.10.1+ee.0'),
          instance_double('tag', type: 'tag', name: '13.10.1+ce.0')
        ]

        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: project, sha: sha, type: 'tag')
          .and_return(tags_with_commit)

        expect(execute).to eq('13.2.0+ee.0')
      end
    end

    context 'when no tag contains commit' do
      let(:merge_request) { instance_double('merge_request', state: 'merged', merge_commit_sha: 'sha') }

      before do
        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: 'gitlab-org/security/gitlab', sha: 'sha', type: 'tag')
          .and_return([])
      end

      it 'returns nil' do
        allow(gitlab)
          .to receive(:refs_containing_commit)
          .with(project: project, sha: sha, type: 'tag')
          .and_return([])

        expect(execute).to be nil
      end
    end
  end
end
