# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::MergeRequestReleaseChecker do
  describe '#execute' do
    subject(:execute) { described_class.new(merge_request_iid, release_version, gitlab_token).execute }

    let(:gitlab_token) { 'token' }
    let(:gitlab) { instance_spy(Chatops::Gitlab::Client) }
    let(:merge_request_iid) { '12345' }
    let(:release_version) { '14.2' }

    before do
      allow(Chatops::Gitlab::Client).to receive(:new).with(token: 'token').and_return(gitlab)
    end

    context 'with invalid version string' do
      let(:release_version) { '14' }

      it 'checks version string format' do
        expect(Chatops::Gitlab::Client).not_to receive(:new)

        expect(execute).to eq(
          "'14' is not a valid monthly release version. Monthly release versions look like 10.0 or 14.2"
        )
      end
    end

    it 'checks if MR does not exist' do
      allow(gitlab)
        .to receive(:merge_request)
        .with('gitlab-org/gitlab', '12345')
        .and_raise(gitlab_error(:NotFound))

      expect(execute).to eq(
        '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> does not exist.'
      )
    end

    it 'checks if MR has been merged' do
      allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)

      allow(gitlab).to receive(:merge_request)
        .with('gitlab-org/gitlab', '12345')
        .and_return(instance_double('merge_request', state: 'opened'))

      expect(execute).to eq(
        '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> has not been merged as yet!'
      )
    end

    context 'when stable branch exists' do
      let(:merge_request) { instance_double('merge_request', state: 'merged', merge_commit_sha: 'sha') }

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)
        allow(gitlab).to receive(:merge_request).with('gitlab-org/gitlab', '12345').and_return(merge_request)

        allow(gitlab)
          .to receive(:branch)
          .with('gitlab-org/security/gitlab', '14-2-stable-ee')
      end

      it 'returns message if branch contains commit' do
        branches_with_commit = [instance_double('branch', type: 'branch', name: '14-2-stable-ee')]

        allow(gitlab)
          .to receive(:commit_refs)
          .with('gitlab-org/security/gitlab', 'sha', hash_including(type: 'branch', per_page: 100))
          .and_return(instance_double('commit_refs', auto_paginate: branches_with_commit))

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> has been included ' \
          'in the <https://gitlab.com/gitlab-org/security/gitlab/-/tree/14-2-stable-ee|stable branch>. ' \
          'This MR will be released in 14.2.'

        expect(execute).to eq(message)
      end

      it 'returns message if branch does not contain commit' do
        branches_with_commit = [instance_double('branch', type: 'branch', name: 'some-branch')]

        allow(gitlab)
          .to receive(:commit_refs)
          .with('gitlab-org/security/gitlab', 'sha', hash_including(type: 'branch', per_page: 100))
          .and_return(instance_double('commit_refs', auto_paginate: branches_with_commit))

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> has not been included ' \
          'in the <https://gitlab.com/gitlab-org/security/gitlab/-/tree/14-2-stable-ee|stable branch>. ' \
          'The MR _will not_ be released in 14.2.'

        expect(execute).to eq(message)
      end
    end

    context 'when stable branch does not exist' do
      let(:merge_request) { instance_double('merge_reqeust', state: 'merged', merge_commit_sha: 'sha') }

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
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)
        allow(gitlab).to receive(:merge_request).with('gitlab-org/gitlab', '12345').and_return(merge_request)

        allow(gitlab)
          .to receive(:branch)
          .with('gitlab-org/security/gitlab', '14-2-stable-ee')
          .and_raise(gitlab_error(:NotFound))

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

      it 'returns message if MR has not been deployed to gprd' do
        allow(gitlab)
          .to receive(:commit_refs)
          .with('gitlab-org/security/gitlab', 'sha', hash_including(type: 'branch', per_page: 100))
          .and_return(instance_double('commit_refs', auto_paginate: []))

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> has not yet been ' \
          'deployed to gprd. It cannot be included in the monthly release until it is deployed to gprd.'

        expect(execute).to eq(message)
      end

      it 'returns message if MR has been deployed to gprd' do
        branches_with_commit = [instance_double('branch', type: 'branch', name: production_status.ref)]

        allow(gitlab)
          .to receive(:commit_refs)
          .with('gitlab-org/security/gitlab', 'sha', hash_including(type: 'branch', per_page: 100))
          .and_return(instance_double('commit_refs', auto_paginate: branches_with_commit))

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|Merge request 12345> has been deployed ' \
          'to gprd. It will most likely be included in release 14.2.'

        expect(execute).to eq(message)
      end
    end
  end
end
