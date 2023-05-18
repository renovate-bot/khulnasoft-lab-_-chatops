# frozen_string_literal: true

require 'spec_helper'

describe Chatops::MergeRequestURLParser do
  let(:mr_url) { 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/123' }
  let(:instance) { described_class.new(mr_url) }

  describe '#valid?' do
    subject { instance }

    it { is_expected.to be_valid }

    context 'with invalid url' do
      let(:mr_url) { 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/' }

      it { is_expected.not_to be_valid }
    end
  end

  describe '#merge_request_project' do
    subject { instance.merge_request_project }

    it { is_expected.to eq('gitlab-org/gitlab') }

    context 'with a single slash' do
      let(:mr_url) { 'https://gitlab.com/gitlab-org/-/merge_requests/123' }

      it { is_expected.to eq('gitlab-org') }
    end
  end

  describe '#merge_request_iid' do
    subject { instance.merge_request_iid }

    it { is_expected.to eq('123') }
  end
end
