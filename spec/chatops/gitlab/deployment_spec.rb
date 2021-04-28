# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Deployment do
  def api_response(ref: 'main', sha: SecureRandom.hex(20), status: 'success')
    # rubocop:disable RSpec/VerifiedDoubles
    double(
      'Gitlab::ObjectifiedHash',
      ref: ref,
      sha: sha,
      status: status
    )
    # rubocop:enable RSpec/VerifiedDoubles
  end

  it 'delegates to the API response object' do
    response = api_response
    deployment = described_class.new(response)

    expect(deployment.ref).to eq(response.ref)
    expect(deployment.sha).to eq(response.sha)
    expect(deployment.status).to eq(response.status)
  end

  describe '#package' do
    it 'formats the ref as a package' do
      response = api_response(ref: '13.12.202105130720+47e0a80b32d.74fa9a18fc5')

      expect(described_class.new(response).package)
        .to eq('13.12.202105130720-47e0a80b32d.74fa9a18fc5')
    end
  end

  describe '#short_sha' do
    it 'returns a shortened SHA' do
      response = api_response(sha: 'a' * 40)

      expect(described_class.new(response).short_sha).to eq('a' * 11)
    end
  end

  describe 'status predicates' do
    it 'checks for a running deployment' do
      response = api_response(status: 'running')

      expect(described_class.new(response)).to be_in_progress
    end

    it 'checks for a successful deployment' do
      response = api_response(status: 'success')

      expect(described_class.new(response)).to be_deployed
    end

    it 'checks for a failed deployment' do
      response = api_response(status: 'failed')

      expect(described_class.new(response)).to be_failed
    end
  end
end
