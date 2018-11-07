# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Project do
  let(:client) { instance_double('client') }
  let(:raw_project) { instance_double('project', id: 1) }
  let(:project) { described_class.new(raw_project, client) }

  describe '#id' do
    it 'returns the ID of the project' do
      expect(project.id).to eq(raw_project.id)
    end
  end

  describe '#add_user' do
    it 'adds a user to the project' do
      user = instance_double('user', id: 4)

      expect(client)
        .to receive(:add_project_member)
        .with(raw_project.id, user.id, 40)

      project.add_user(user, 40)
    end
  end

  describe '#remove_user' do
    it 'removes a user from the project' do
      user = instance_double('user', id: 4)

      expect(client)
        .to receive(:remove_project_member)
        .with(raw_project.id, user.id)

      project.remove_user(user)
    end
  end
end
