# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::Group do
  let(:client) { instance_double('client') }
  let(:raw_group) { instance_double('group', id: 1) }
  let(:group) { described_class.new(raw_group, client) }

  describe '#id' do
    it 'returns the ID of the group' do
      expect(group.id).to eq(raw_group.id)
    end
  end

  describe '#add_user' do
    it 'adds a user to the group' do
      user = instance_double('user', id: 4)

      expect(client)
        .to receive(:add_group_member)
        .with(raw_group.id, user.id, 40)

      group.add_user(user, 40)
    end
  end

  describe '#remove_user' do
    it 'removes a user from the group' do
      user = instance_double('user', id: 4)

      expect(client)
        .to receive(:remove_group_member)
        .with(raw_group.id, user.id)

      group.remove_user(user)
    end
  end
end
