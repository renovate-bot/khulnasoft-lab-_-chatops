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
    end

    it 'updates all tasks with the specified attributes' do
      tasks = [
        instance_double(
          'task',
          id: 1,
          description: 'auto_deploy:foo',
          owner: instance_double('user', username: 'jim')
        ),
        instance_double(
          'task',
          id: 2,
          description: 'auto_deploy:bar',
          owner: instance_double('user', username: 'jim')
        )
      ]
      attrs = {
        active: false
      }

      allow(fake_client).to receive(:pipeline_schedules).and_return(tasks)

      expect(fake_client).to receive(:pipeline_schedule_take_ownership)
        .with(described_class::TASK_PROJECT, tasks.first.id)
        .with(described_class::TASK_PROJECT, tasks.last.id)

      expect(fake_client).to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, tasks.first.id, **attrs)
      expect(fake_client).to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, tasks.last.id, **attrs)

      auto_deploy.update_tasks(attrs)
    end

    it 'does not call pipeline_schedule_take_ownership if owner is release tools bot' do
      tasks = [
        instance_double(
          'task',
          id: 1,
          description: 'auto_deploy:foo',
          owner: instance_double('user', username: 'gitlab-release-tools-bot')
        ),
        instance_double(
          'task',
          id: 2,
          description: 'auto_deploy:bar',
          owner: instance_double('user', username: 'gitlab-release-tools-bot')
        )
      ]
      attrs = {
        active: false
      }

      allow(fake_client).to receive(:pipeline_schedules).and_return(tasks)

      expect(fake_client).not_to receive(:pipeline_schedule_take_ownership)

      auto_deploy.update_tasks(attrs)
    end

    it 'raises an exception if no tasks are found' do
      tasks = [
        instance_double('task', id: 1, description: 'release_manager:sync')
      ]

      allow(fake_client).to receive(:pipeline_schedules).and_return(tasks)

      expect { auto_deploy.update_tasks(active: false) }
        .to raise_error(RuntimeError, /No auto_deploy tasks found/)
    end
  end

  describe '#unpause_prepare' do
    it 'resumes the prepare task' do
      task = instance_double(
        'task',
        id: 42,
        description: 'auto_deploy:prepare',
        owner: instance_double('user', username: 'jim')
      )

      allow(fake_client)
        .to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, 42, active: true)

      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([task])

      expect(fake_client)
        .to receive(:pipeline_schedule_take_ownership)
        .with(described_class::TASK_PROJECT, 42)

      auto_deploy.unpause_prepare

      expect(fake_client).to have_received(:edit_pipeline_schedule)
    end

    it 'does not call pipeline_schedule_take_ownership if owner is release tools bot' do
      task = instance_double(
        'task',
        id: 42,
        description: 'auto_deploy:prepare',
        owner: instance_double('user', username: 'gitlab-release-tools-bot')
      )

      allow(fake_client)
        .to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, 42, active: true)

      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([task])

      expect(fake_client).not_to receive(:pipeline_schedule_take_ownership)

      auto_deploy.unpause_prepare
    end

    it 'raises when there is no prepare task' do
      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([])

      expect { auto_deploy.unpause_prepare }.to raise_error(RuntimeError)
    end
  end

  describe '#pause_prepare' do
    it 'pauses the prepare task' do
      task = instance_double(
        'task',
        id: 42,
        description: 'auto_deploy:prepare',
        owner: instance_double('user', username: 'jim')
      )

      allow(fake_client)
        .to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, 42, active: false)

      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([task])

      expect(fake_client)
        .to receive(:pipeline_schedule_take_ownership)
        .with(described_class::TASK_PROJECT, 42)

      auto_deploy.pause_prepare

      expect(fake_client).to have_received(:edit_pipeline_schedule)
    end

    it 'does not call pipeline_schedule_take_ownership if owner is release tools bot' do
      task = instance_double(
        'task',
        id: 42,
        description: 'auto_deploy:prepare',
        owner: instance_double('user', username: 'gitlab-release-tools-bot')
      )

      allow(fake_client)
        .to receive(:edit_pipeline_schedule)
        .with(described_class::TASK_PROJECT, 42, active: false)

      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([task])

      expect(fake_client).not_to receive(:pipeline_schedule_take_ownership)

      auto_deploy.pause_prepare
    end

    it 'raises when there is no prepare task' do
      allow(fake_client)
        .to receive(:pipeline_schedules)
        .and_return([])

      expect { auto_deploy.pause_prepare }.to raise_error(RuntimeError)
    end
  end
end
