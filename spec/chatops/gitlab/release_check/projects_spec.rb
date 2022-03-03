# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::Projects do
  describe '.security_project_for' do
    using RSpec::Parameterized::TableSyntax

    where(:project, :security_project) do
      described_class::GITLAB_SECURITY   | described_class::GITLAB_SECURITY
      described_class::GITLAB_CANONICAL  | described_class::GITLAB_SECURITY
      described_class::OMNIBUS_SECURITY  | described_class::OMNIBUS_SECURITY
      described_class::OMNIBUS_CANONICAL | described_class::OMNIBUS_SECURITY
    end

    with_them do
      specify { expect(described_class.security_project_for(project)).to eq(security_project) }
    end
  end
end
