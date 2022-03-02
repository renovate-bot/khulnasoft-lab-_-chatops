# frozen_string_literal: true

module Chatops
  module Gitlab
    module ReleaseCheck
      class LowestTag
        # We ignore RCs since RCs are created from the stable branch,
        # and we already check the stable branch.
        # v14.7.0-ee
        GITLAB_TAG_REGEX = /\Av(?<version>\d+\.\d+\.\d+)-ee\z/

        # 14.7.0+ee.0
        OMNIBUS_TAG_REGEX = /\A(?<version>\d+\.\d+\.\d+)\+ee\.\d+\z/

        def initialize(client, project, commit_sha)
          @client = client
          @project = project
          @sha = commit_sha
        end

        # Returns the lowest tag that contains the given commit SHA.
        #
        # @return [String, nil] Returns nil if no tag contains the commit, or returns
        #                       the lowest tag that contains it. Ex: `v14.2.3`
        def execute
          return if all_tags_containing_commit.empty?

          all_tags_containing_commit
            .min_by { |t| t[:version] }
            .fetch(:name)
        end

        private

        attr_reader :client, :project, :sha

        def all_tags_containing_commit
          @all_tags_containing_commit ||=
            client
              .refs_containing_commit(project: project, type: 'tag', sha: sha)
              .collect do |t|
                groups = tag_regex.match(t.name)
                # Some old tags don't follow the naming conventions, so groups will be nil.
                # For example 11-10-0cfa69752d8-0d9531c80-ee.
                next unless groups

                {
                  # Gem::Version is used because it provides comparison operators allowing
                  # us to sort the versions.
                  # groups[:version] is a string of format `major.minor.patch` (ex: 12.10.3).
                  version: Gem::Version.new(groups[:version]),
                  name: t.name
                }
              end
              .compact
        end

        def tag_regex
          @tag_regex ||=
            if Projects::GITLAB_SECURITY == project
              GITLAB_TAG_REGEX
            elsif Projects::OMNIBUS_SECURITY == project
              OMNIBUS_TAG_REGEX
            end
        end
      end
    end
  end
end
