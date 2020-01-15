# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::AutoDeploy do
  subject(:auto_deploy) { described_class.new(fake_client) }

  let(:fake_client) { spy }

  describe '#tasks' do
    it 'returns an Array of scheduled `auto_deploy` tasks' do
      tasks = [
        instance_double('task', description: 'auto_deploy:tag'),
        instance_double('task', description: 'release_managers:sync')
      ]

      expect(fake_client).to receive(:pipeline_schedules)
        .with(described_class::TASK_PROJECT)
        .and_return(tasks)

      expect(auto_deploy.tasks).to contain_exactly(tasks.first)
    end
  end

  describe '#update_tasks' do
    let(:tasks) do
      [
        instance_double('task', id: 1, description: 'auto_deploy:foo'),
        instance_double('task', id: 2, description: 'auto_deploy:bar')
      ]
    end

    before do
      allow(fake_client).to receive(:pipeline_schedules).and_return(tasks)
    end

    it 'updates all tasks with the specified attributes' do
      attrs = {
        active: false
      }

      expect(fake_client).to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, tasks.first.id, **attrs)
      expect(fake_client).to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, tasks.last.id, **attrs)

      auto_deploy.update_tasks(attrs)
    end
  end
end
