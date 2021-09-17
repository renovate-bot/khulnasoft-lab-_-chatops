# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::MergeRequestReleaseChecker do
  describe '#execute' do
    subject(:execute) { described_class.new(merge_request_url, release_version, gitlab_token).execute }

    let(:gitlab_token) { 'token' }
    let(:gitlab) { instance_spy(Chatops::Gitlab::Client) }
    let(:merge_request_url) { 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345' }
    let(:release_version) { '14.2' }

    before do
      allow(Chatops::Gitlab::Client).to receive(:new).with(token: 'token').and_return(gitlab)
    end

    context 'with invalid version string' do
      let(:release_version) { '14' }

      it 'checks version string format' do
        expect(Chatops::Gitlab::Client).not_to receive(:new)

        expect(execute).to eq(
          "'14' is not a valid monthly release version. Monthly release versions look like 10.0 or 14.2."
        )
      end
    end

    context 'with invalid merge request url' do
      let(:merge_request_url) { '12345' }

      it 'checks merge request url' do
        expect(Chatops::Gitlab::Client).not_to receive(:new)

        expect(execute).to eq('12345 is not a valid merge request URL.')
      end
    end

    context 'with merge request from unsupported project' do
      let(:merge_request_url) { 'https://gitlab.com/gitlab-org/omnibus-gitlab/-/merge_requests/12345' }

      it 'checks merge request url' do
        expect(Chatops::Gitlab::Client).not_to receive(:new)

        message =
          'Only merge requests from ["gitlab-org/gitlab", "gitlab-org/security/gitlab"] ' \
          'are currently supported.'

        expect(execute).to eq(message)
      end
    end

    it 'checks if MR does not exist' do
      allow(gitlab)
        .to receive(:merge_request)
        .with('gitlab-org/gitlab', '12345')
        .and_raise(gitlab_error(:NotFound))

      expect(execute).to eq(
        '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> does not exist.'
      )
    end

    it 'checks if MR has been merged' do
      allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)

      allow(gitlab).to receive(:merge_request)
        .with('gitlab-org/gitlab', '12345')
        .and_return(instance_double('merge_request', state: 'opened'))

      expect(execute).to eq(
        '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> has not been merged as yet!'
      )
    end

    context 'with security project merge request' do
      let(:merge_request_url) { 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/12345' }

      it 'checks the security project' do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)

        allow(gitlab).to receive(:merge_request)
          .with('gitlab-org/security/gitlab', '12345')
          .and_return(instance_double('merge_request', state: 'opened'))

        message = '<https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/12345|gitlab-org/security/gitlab!12345> has not been merged as yet!'

        expect(execute).to eq(message)
      end
    end

    context 'when commit is present in tags' do
      let(:release_version) { nil }
      let(:merge_request) { instance_double('merge_request', state: 'merged', merge_commit_sha: 'sha') }

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)
        allow(gitlab).to receive(:merge_request).with('gitlab-org/gitlab', '12345').and_return(merge_request)
      end

      it 'returns the lowest tag message' do
        lowest_tag_service = instance_spy(Chatops::Gitlab::ReleaseCheck::LowestTag, execute: 'v13.2.0-ee')
        allow(Chatops::Gitlab::ReleaseCheck::LowestTag).to receive(:new).and_return(lowest_tag_service)

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> was ' \
          'first released in <https://gitlab.com/gitlab-org/security/gitlab/-/tree/v13.2.0-ee|v13.2.0-ee>.'

        expect(execute).to eq(message)
      end
    end

    context 'when no tag contains commit' do
      let(:merge_request) { instance_double('merge_request', state: 'merged', merge_commit_sha: 'sha') }

      let(:stable_branch_service) do
        instance_spy(
          Chatops::Gitlab::ReleaseCheck::StableBranch,
          name: '14-2-stable-ee',
          exists?: true
        )
      end

      before do
        allow(Chatops::Gitlab::Client).to receive(:new).and_return(gitlab)
        allow(gitlab).to receive(:merge_request).with('gitlab-org/gitlab', '12345').and_return(merge_request)

        lowest_tag_service = instance_spy(Chatops::Gitlab::ReleaseCheck::LowestTag, execute: nil)
        allow(Chatops::Gitlab::ReleaseCheck::LowestTag).to receive(:new).and_return(lowest_tag_service)

        allow(Chatops::Gitlab::ReleaseCheck::StableBranch).to receive(:new).and_return(stable_branch_service)
      end

      it 'does not check stable branch if version is not specified' do
        version = nil
        result = described_class.new(merge_request_url, version, gitlab_token).execute

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> was not ' \
          'released in any past version. Try checking with the upcoming release version. Ex: `release check <MR URL> 14.2`'

        expect(Chatops::Gitlab::ReleaseCheck::StableBranch).not_to receive(:new)
        expect(result).to eq(message)
      end

      it 'returns message if branch contains commit' do
        allow(stable_branch_service)
          .to receive(:contains_commit?)
          .with('sha')
          .and_return(true)

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> has been included ' \
          'in the <https://gitlab.com/gitlab-org/security/gitlab/-/tree/14-2-stable-ee|stable branch>. ' \
          'This MR will be released in 14.2.'

        expect(execute).to eq(message)
      end

      it 'returns message if branch does not contain commit' do
        allow(stable_branch_service)
          .to receive(:contains_commit?)
          .with('sha')
          .and_return(false)

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> has not been included ' \
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

        lowest_tag_service = instance_spy(Chatops::Gitlab::ReleaseCheck::LowestTag, execute: nil)
        allow(Chatops::Gitlab::ReleaseCheck::LowestTag).to receive(:new).and_return(lowest_tag_service)

        stable_branch_service = instance_spy(Chatops::Gitlab::ReleaseCheck::StableBranch, name: '14-2-stable-ee', exists?: false)
        allow(Chatops::Gitlab::ReleaseCheck::StableBranch).to receive(:new).and_return(stable_branch_service)
      end

      it 'returns message if MR has not been deployed to gprd' do
        commit = instance_spy(Chatops::Gitlab::ReleaseCheck::Commit, deployed_to_gprd?: false)
        allow(Chatops::Gitlab::ReleaseCheck::Commit).to receive(:new).and_return(commit)

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> has not yet been ' \
          'deployed to gprd. It cannot be included in the monthly release until it is deployed to gprd.'

        expect(execute).to eq(message)
      end

      it 'returns message if MR has been deployed to gprd' do
        commit = instance_spy(Chatops::Gitlab::ReleaseCheck::Commit, deployed_to_gprd?: true)
        allow(Chatops::Gitlab::ReleaseCheck::Commit).to receive(:new).and_return(commit)

        message =
          '<https://gitlab.com/gitlab-org/gitlab/-/merge_requests/12345|gitlab-org/gitlab!12345> has been deployed ' \
          'to gprd. It will most likely be included in release 14.2.'

        expect(execute).to eq(message)
      end
    end
  end
end
