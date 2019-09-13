# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Member do
  describe '.perform' do
    it 'supports a --staging option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[add foo bar],
          hash_including(staging: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[add foo bar --staging])
    end

    it 'supports a --dev option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[add foo bar],
          hash_including(dev: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[add foo bar --dev])
    end

    it 'supports a --ops option' do
      instance = instance_double('instance')

      expect(described_class)
        .to receive(:new)
        .with(
          %w[add foo bar],
          hash_including(ops: true),
          {}
        )
        .and_return(instance)

      expect(instance)
        .to receive(:perform)

      described_class.perform(%w[add foo bar --ops])
    end
  end

  describe '#perform' do
    context 'when using an unsupported command' do
      it 'returns an error message' do
        command = described_class.new(%w[foo])

        expect(command.perform).to match(/The subcommand is invalid/)
      end
    end

    context 'when using the add command' do
      it 'adds a member' do
        command = described_class.new(%w[add foo bar])

        expect(command).to receive(:add)

        command.perform
      end
    end

    context 'when using the remove command' do
      it 'removes a member' do
        command = described_class.new(%w[remove foo bar])

        expect(command).to receive(:remove)

        command.perform
      end
    end

    context 'when a command raises an API response error' do
      it 'returns an error message' do
        command = described_class.new(%w[add foo bar])

        response = instance_double(
          'response',
          code: 401,
          request: instance_double('request', base_uri: 'foo', path: '/foo'),
          parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
        )

        allow(command)
          .to receive(:add)
          .and_raise(Gitlab::Error::ResponseError.new(response))

        expect(command.perform).to eq('Failed to add foo: error')
      end
    end

    context 'when a command raises ArgumentError' do
      it 'returns an error message' do
        command = described_class.new(%w[add foo bar])

        allow(command)
          .to receive(:add)
          .and_raise(ArgumentError.new('error'))

        expect(command.perform).to eq('Failed to add foo: error')
      end
    end
  end

  describe '#unsupported_command' do
    it 'returns a help message' do
      expect(described_class.new.unsupported_command).to eq(<<~MSG.strip)
        The subcommand is invalid. The following subcommands are available:

        * `add`
        * `remove`

        For more information run `member --help`.
      MSG
    end
  end

  describe '#add' do
    it 'adds a user to a project' do
      command = described_class
        .new(%w[add alice gitlab-org/gitlab-foss], { level: 'developer' }, {})

      project = instance_double('project')
      user = instance_double('user')

      allow(command)
        .to receive(:find_group_or_project!)
        .and_return(project)

      allow(command)
        .to receive(:find_user!)
        .and_return(user)

      expect(project)
        .to receive(:add_user)
        .with(user, described_class::ACCESS_LEVELS['developer'])

      expect(command.add)
        .to eq('alice has been added to gitlab-org/gitlab-foss')
    end

    it 'adds a user to a project with maintainer access' do
      command = described_class
        .new(%w[add alice gitlab-org/gitlab-foss], { level: 'maintainer' }, {})

      project = instance_double('project')
      user = instance_double('user')

      allow(command)
        .to receive(:find_group_or_project!)
        .and_return(project)

      allow(command)
        .to receive(:find_user!)
        .and_return(user)

      expect(project)
        .to receive(:add_user)
        .with(user, described_class::ACCESS_LEVELS['maintainer'])

      expect(command.add)
        .to eq('alice has been added to gitlab-org/gitlab-foss')
    end
  end

  describe '#remove' do
    it 'removes a user from a project' do
      command = described_class.new(%w[remove alice gitlab-org/gitlab-foss])
      project = instance_double('project')
      user = instance_double('user')

      allow(command)
        .to receive(:find_group_or_project!)
        .and_return(project)

      allow(command)
        .to receive(:find_user!)
        .and_return(user)

      expect(project)
        .to receive(:remove_user)
        .with(user)

      expect(command.remove)
        .to eq('alice has been removed from gitlab-org/gitlab-foss')
    end
  end

  describe '#username!' do
    context 'without a username!' do
      it 'raises ArgumentError' do
        command = described_class.new

        expect { command.username! }.to raise_error(ArgumentError)
      end
    end

    context 'with a username!' do
      it 'returns the username!' do
        command = described_class.new(%w[add alice])

        expect(command.username!).to eq('alice')
      end
    end
  end

  describe '#project_or_group_name!' do
    context 'without a project or group name' do
      it 'raises ArgumentError' do
        command = described_class.new

        expect { command.project_or_group_name! }.to raise_error(ArgumentError)
      end
    end

    context 'with a project name' do
      it 'returns the project name' do
        command = described_class.new(%w[add alice gitlab-org/gitlab-foss])

        expect(command.project_or_group_name!).to eq('gitlab-org/gitlab-foss')
      end
    end
  end

  describe '#access_level!' do
    context 'without an access level' do
      it 'raises ArgumentError' do
        command = described_class.new

        expect { command.access_level! }.to raise_error(ArgumentError)
      end
    end

    context 'with an invalid access level' do
      it 'raises ArgumentError' do
        command = described_class.new([], { level: 'foo' }, {})

        expect { command.access_level! }.to raise_error(ArgumentError)
      end
    end

    context 'with a valid access level' do
      it 'returns the numeric value of the access level' do
        command = described_class.new([], { level: 'maintainer' }, {})

        expect(command.access_level!)
          .to eq(described_class::ACCESS_LEVELS['maintainer'])
      end
    end
  end

  describe '#find_user!' do
    context 'with an invalid username' do
      it 'raises ArgumentError' do
        command = described_class
          .new(%w[add alice], {}, 'GITLAB_TOKEN' => '123')

        allow(command.client)
          .to receive(:find_user)
          .with('alice')
          .and_return(nil)

        expect { command.find_user! }.to raise_error(ArgumentError)
      end
    end

    context 'with a valid username' do
      it 'returns the user' do
        command = described_class
          .new(%w[add alice], {}, 'GITLAB_TOKEN' => '123')

        user = instance_double('user')

        allow(command.client)
          .to receive(:find_user)
          .with('alice')
          .and_return(user)

        expect(command.find_user!).to eq(user)
      end
    end
  end

  describe '#find_group_or_project!' do
    let(:missing_response) do
      instance_double(
        'response',
        code: 404,
        request: instance_double('request', base_uri: 'foo', path: '/foo'),
        parsed_response: Gitlab::ObjectifiedHash.new(message: 'error')
      )
    end

    let(:command) do
      described_class.new(%w[add alice foo], {}, 'GITLAB_TOKEN' => '123')
    end

    context 'with an invalid project and group name' do
      it 'raises ArgumentError' do
        allow(command.client)
          .to receive(:find_group)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        allow(command.client)
          .to receive(:find_project)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        expect { command.find_group_or_project! }.to raise_error(ArgumentError)
      end
    end

    context 'with a valid group name' do
      it 'returns the group' do
        group = instance_double('group')

        allow(command.client)
          .to receive(:find_group)
          .and_return(group)

        expect(command.find_group_or_project!)
          .to be_an_instance_of(Chatops::Gitlab::Group)
      end
    end

    context 'with an invalid group name and valid project name' do
      it 'returns the project' do
        project = instance_double('project')

        allow(command.client)
          .to receive(:find_group)
          .and_raise(Gitlab::Error::NotFound.new(missing_response))

        allow(command.client)
          .to receive(:find_project)
          .and_return(project)

        expect(command.find_group_or_project!)
          .to be_an_instance_of(Chatops::Gitlab::Project)
      end
    end
  end

  describe '#client' do
    it 'returns an instance of Chatops::Gitlab::Client' do
      command = described_class.new([], {}, 'GITLAB_TOKEN' => '123')

      expect(command.client).to be_instance_of(Chatops::Gitlab::Client)
    end
  end
end
