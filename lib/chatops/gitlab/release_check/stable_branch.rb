# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class StableBranch
        def initialize(client, project, version)
          @client = client
          @project = project
          @version = version
        end

        def exists?
          client.branch(project, name)

          true
        rescue ::Gitlab::Error::NotFound
          false
        end

        def contains_commit?(sha)
          client
            .refs_containing_commit(project: project, type: 'branch', sha: sha)
            .select { |branch| branch.name == name }
            .length >= 1
        end

        def name
          @name ||= "#{version.tr('.', '-')}-stable-ee"
        end

        private

        attr_reader :client, :project, :version
      end
    end
  end
end
