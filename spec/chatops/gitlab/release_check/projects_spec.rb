# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::ReleaseCheck::Projects do
  describe '.security_project_for' do
    using RSpec::Parameterized::TableSyntax

    where(:project, :security_project) do
      # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
      described_class::GITLAB_SECURITY | described_class::GITLAB_SECURITY
      described_class::GITLAB_CANONICAL | described_class::GITLAB_SECURITY
      described_class::OMNIBUS_SECURITY | described_class::OMNIBUS_SECURITY
      described_class::OMNIBUS_CANONICAL | described_class::OMNIBUS_SECURITY
      # rubocop:enable Lint/BinaryOperatorWithIdenticalOperands
    end
    with_them do
      specify { expect(described_class.security_project_for(project)).to eq(security_project) }
    end
  end
end
