# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::SecurityMirrorStatus do
  def mirror_stub(messages = {})
    defaults = {
      enabled: true,
      last_error: nil,
      url: 'https://******:******@example.com/gitlab-org/gitlab.git'
    }

    instance_double('status', defaults.merge(messages))
  end

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
      status = described_class.new(project)
      allow(status).to receive(:client).and_return(client)

      mirror = mirror_stub(
        last_error: 'failure',
        url: 'https://***:***@gitlab.com/gitlab-org/security/gitlab.git'
      )
      expect(client).to receive(:get).and_return([mirror])

      expect(status.security_error).to eq('failure')
    end
  end

  describe '#build_error' do
    it 'returns the last error for the build mirror' do
      status = described_class.new(project)
      allow(status).to receive(:client).and_return(client)

      mirror = mirror_stub(
        url: 'https://***:***@dev.gitlab.org/gitlab/gitlab-ee.git',
        last_error: 'failure'
      )
      expect(client).to receive(:get).and_return([mirror])

      expect(status.build_error).to eq('failure')
    end
  end

  describe '#mirror_chain' do
    it 'shows a broken chain due to disabled mirrors' do
      status = described_class.new(project)

      allow(status).to receive(:security_status)
        .and_return(mirror_stub(enabled: false))
      allow(status).to receive(:build_status)
        .and_return(mirror_stub(enabled: false))

      chain = status.mirror_chain

      expect(chain).to include('|Canonical> :double_vertical_bar:')
      expect(chain).to include('|Security> :double_vertical_bar:')
      expect(chain).to end_with(':warning:')
    end

    it 'shows a broken chain due to mirror errors' do
      status = described_class.new(project)

      allow(status).to receive(:security_status)
        .and_return(mirror_stub(last_error: 'foo'))
      allow(status).to receive(:build_status)
        .and_return(mirror_stub(last_error: 'bar'))

      chain = status.mirror_chain

      expect(chain).to include('|Canonical> :x:')
      expect(chain).to include('|Security> :x:')
      expect(chain).to end_with(':warning:')
    end

    it 'shows a complete chain' do
      status = described_class.new(project)

      allow(status).to receive(:security_status)
        .and_return(mirror_stub)
      allow(status).to receive(:build_status)
        .and_return(mirror_stub)

      chain = status.mirror_chain

      expect(chain).to include('|Canonical> :arrow_right:')
      expect(chain).to include('|Security> :arrow_right:')
      expect(chain).to end_with(':white_check_mark:')
    end
  end
end
