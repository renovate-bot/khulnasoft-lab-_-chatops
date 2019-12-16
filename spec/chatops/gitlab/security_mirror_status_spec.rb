# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::SecurityMirrorStatus do
  let(:client) { Chatops::Gitlab::Client.new(token: 'token').internal_client }
  let(:project) do
    {
      'path_with_namespace' => 'gitlab-org/security/gitlab',
      'forked_from_project' => {
        'path_with_namespace' => 'gitlab-org/gitlab'
      }
    }
  end

  describe '#available?' do
    let(:client) { instance_double('client', url_encode: '') }

    it 'returns true when all mirror statuses are available' do
      instance = described_class.new(double.as_null_object)

      allow(instance).to receive(:security_status).and_return(true)
      allow(instance).to receive(:build_status).and_return(true)

      expect(instance).to be_available
    end

    it 'returns false when Build status is unavailable' do
      instance = described_class.new(double.as_null_object)

      allow(instance).to receive(:client).and_return(client)
      allow(instance).to receive(:security_status).and_return(true)
      allow(client).to receive(:get)
        .and_raise(gitlab_error(:NotFound, code: 404))

      expect(instance).not_to be_available
    end

    it 'returns false when Security status is unavailable' do
      instance = described_class.new(double.as_null_object)

      allow(instance).to receive(:client).and_return(client)
      allow(client).to receive(:get)
        .and_raise(gitlab_error(:NotFound, code: 404))
      expect(instance).not_to receive(:build_status)

      expect(instance).not_to be_available
    end
  end

  describe '#security_error' do
    it 'returns the last error for the security mirror' do
      mirror = instance_double(
        'mirror',
        url: 'https://***:***@gitlab.com/gitlab-org/security/gitlab.git',
        last_error: 'failure'
      )

      status = described_class.new(project)

      allow(status).to receive(:client).and_return(client)
      expect(client).to receive(:get).and_return([mirror])

      expect(status.security_error).to eq('failure')
    end
  end

  describe '#build_error' do
    it 'returns the last error for the build mirror' do
      mirror = instance_double(
        'mirror',
        url: 'https://***:***@dev.gitlab.org/gitlab/gitlab-ee.git',
        last_error: 'failure'
      )

      status = described_class.new(project)

      allow(status).to receive(:client).and_return(client)
      expect(client).to receive(:get).and_return([mirror])

      expect(status.build_error).to eq('failure')
    end
  end

  describe '#mirror_chain' do
    it 'shows a broken chain' do
      status = described_class.new(project)

      allow(status).to receive(:security_status)
        .and_return(instance_double('status', last_error: 'foo'))
      allow(status).to receive(:build_status)
        .and_return(instance_double('status', last_error: 'bar', url: ''))

      chain = status.mirror_chain

      expect(chain).to include('|Canonical> :x:')
      expect(chain).to include('|Security> :x:')
      expect(chain).to end_with(':warning:')
    end

    it 'shows a complete chain' do
      status = described_class.new(project)

      allow(status).to receive(:security_status)
        .and_return(instance_double('status', last_error: nil))
      allow(status).to receive(:build_status)
        .and_return(instance_double('status', last_error: nil, url: ''))

      chain = status.mirror_chain

      expect(chain).to include('|Canonical> :arrow_right:')
      expect(chain).to include('|Security> :arrow_right:')
      expect(chain).to end_with(':white_check_mark:')
    end
  end
end
