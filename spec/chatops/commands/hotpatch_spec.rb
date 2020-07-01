# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Hotpatch do
  let(:chef_client) { instance_spy(Chatops::Chef::Client) }
  let(:gitlab_client) { instance_spy(Gitlab::Client) }
  let(:fake_mr) do
    instance_double(
      'mr',
      web_url: 'https://gitlab.example.com/proj/-/merge_requests/9000',
      iid: '9000'
    )
  end
  let(:fake_branch) do
    instance_double('branch', web_url: 'https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-branch')
  end
  let(:fake_file) do
    instance_double('file', file_path: 'patcher/fake-file/.gitkeep')
  end

  def ci_env
    {
      'CHEF_USERNAME' => 'fake-user',
      'CHEF_PEM_KEY' => 'fake-pem',
      'GITLAB_USER_LOGIN' => 'fake-user',
      'GITLAB_OPS_TOKEN' => 'fake-token'
    }
  end

  describe '#perform' do
    let(:command) do
      described_class.new(
        [], { incident: 1234 },
        ci_env
      )
    end
    let(:command_with_pkg) do
      described_class.new(
        [], { incident: 1234, package: 'some-pkg' },
        ci_env
      )
    end

    let(:mr_description) do
      <<~MR_DESC.chomp
        @fake-user has initiated a hot patch for incident https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234

        Please see the [release-docs](https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md) for instructions
      MR_DESC
    end

    before do
      allow(Chatops::Chef::Client).to receive(:new).and_return(chef_client)
      allow(Gitlab::Client).to receive(:new).and_return(gitlab_client)

      allow(gitlab_client).to receive(:create_merge_request).and_return(fake_mr)
      allow(gitlab_client).to receive(:create_branch).and_return(fake_branch)
      allow(gitlab_client).to receive(:create_file).and_return(fake_file)
    end

    context 'when staging and production have the same version' do
      let(:patch_result) do
        <<~PATCH_RESULT.chomp
          Initiated a hot patch for incident <https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234|#1234>
          :swiss-tanuki: :swiss-tanuki: :swiss-tanuki:
          • :git-branch: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-branch|fake-user-1234>
          • *production*: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-user-1234/patcher/fake-file/.gitkeep|patch directory>
          • :mr: MR <https://gitlab.example.com/proj/-/merge_requests/9000|!9000>

          Please see the <https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md|release docs> for instructions
        PATCH_RESULT
      end

      before do
        allow(chef_client).to receive(:package_version).and_return(
          '13.2.some-version'
        )
      end

      it 'creates patch' do
        expect(command.perform).to eq(patch_result)

        %w[gstg gprd].each do |e|
          expect(chef_client).to have_received(:package_version).once.with(e)
        end

        expect(gitlab_client).to have_received(:create_file).with(
          'gitlab-com/engineering/patcher',
          'patches/13.2.some-version/.gitkeep',
          'fake-user-1234',
          '',
          'Creating patch dir for ' \
            '13.2.some-version'
        )

        expect(gitlab_client).to have_received(:create_merge_request).with(
          'gitlab-com/engineering/patcher',
          'Hot patch for https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234',
          description: mr_description,
          remove_source_branch: true,
          source_branch: 'fake-user-1234',
          target_branch: 'master'
        )
      end
    end

    context 'when staging and production have the different versions' do
      let(:patch_result) do
        <<~PATCH_RESULT.chomp
          Initiated a hot patch for incident <https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234|#1234>
          :swiss-tanuki: :swiss-tanuki: :swiss-tanuki:
          • :git-branch: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-branch|fake-user-1234>
          • *production*: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-user-1234/patcher/fake-file/.gitkeep|patch directory>
          • *canary*: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-user-1234/patcher/fake-file/.gitkeep|patch directory>
          • *staging*: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-user-1234/patcher/fake-file/.gitkeep|patch directory>
          • :mr: MR <https://gitlab.example.com/proj/-/merge_requests/9000|!9000>

          Please see the <https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md|release docs> for instructions
        PATCH_RESULT
      end

      before do
        allow(chef_client).to receive(:package_version).with('gprd').and_return(
          '13.2.some-gprd-version'
        )
        allow(chef_client).to receive(:package_version).with(
          'gprd-cny'
        ).and_return(
          '13.2.some-cny-version'
        )
        allow(chef_client).to receive(:package_version).with('gstg').and_return(
          '13.2.some-gstg-version'
        )
      end

      it 'creates patch' do
        expect(command.perform).to eq(patch_result)

        %w[gprd gprd-cny gstg].each do |e|
          expect(chef_client).to have_received(:package_version).once.with(e)
        end

        %w[
          13.2.some-gprd-version
          13.2.some-cny-version
          13.2.some-gstg-version
        ].each do |v|
          expect(gitlab_client).to have_received(:create_file).once.with(
            'gitlab-com/engineering/patcher',
            "patches/#{v}/.gitkeep",
            'fake-user-1234',
            '',
            "Creating patch dir for #{v}"
          )
        end
        expect(gitlab_client).to have_received(:create_merge_request).with(
          'gitlab-com/engineering/patcher',
          'Hot patch for https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234',
          description: mr_description,
          remove_source_branch: true,
          source_branch: 'fake-user-1234',
          target_branch: 'master'
        )
      end
    end

    context 'when a package is specified explicitly' do
      let(:patch_result) do
        <<~PATCH_RESULT.chomp
          Initiated a hot patch for incident <https://gitlab.com/gitlab-com/gl-infra/production/-/issues/1234|#1234>
          :swiss-tanuki: :swiss-tanuki: :swiss-tanuki:
          • :git-branch: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-branch|fake-user-1234>
          • *unknown env*: <https://ops.gitlab.net/gitlab-com/engineering/patcher/-/tree/fake-user-1234/patcher/fake-file/.gitkeep|patch directory>
          • :mr: MR <https://gitlab.example.com/proj/-/merge_requests/9000|!9000>

          Please see the <https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md|release docs> for instructions
        PATCH_RESULT
      end

      before do
        allow(chef_client).to receive(:package_version).and_return(
          '13.2.some-version'
        )
      end

      it 'creates patch' do
        expect(command_with_pkg.perform).to eq(patch_result)

        expect(chef_client).not_to have_received(:package_version)

        expect(gitlab_client).to have_received(:create_file).with(
          'gitlab-com/engineering/patcher',
          'patches/some-pkg/.gitkeep',
          'fake-user-1234',
          '',
          'Creating patch dir for ' \
            'some-pkg'
        )
      end
    end
  end
end
