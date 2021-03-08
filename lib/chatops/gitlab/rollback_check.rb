# frozen_string_literal: true

module Chatops
  module Gitlab
    # Performs checks to see if a diff set is safe to roll back
    class RollbackCheck
      SAFE_ICON = ':large_green_circle:'
      UNSAFE_ICON = ':red_circle:'

      # Number of new migrations in the diff
      attr_reader :new_migrations

      # Number of new post-deploy migrations in the diff
      attr_reader :new_post_deploy_migrations

      # compare - Gitlab::ObjectifiedHash from a compare API call
      #           See https://docs.gitlab.com/ee/api/repositories.html#compare-branches-tags-or-commits
      def initialize(compare)
        @compare = compare

        @new_migrations = 0
        @new_post_deploy_migrations = 0
      end

      def execute
        @compare.diffs.each do |diff|
          if new_migration?(diff)
            @new_migrations += 1
          elsif new_post_deploy_migration?(diff)
            @new_post_deploy_migrations += 1
          end
        end

        self
      end

      def safe?
        new_post_deploy_migrations.zero? && !timeout?
      end

      def slack_block(blocks)
        lines = []

        blocks.section do |block|
          if safe?
            lines << "#{SAFE_ICON} Safe to roll back"
          else
            lines << "#{UNSAFE_ICON} *Potentially unsafe to roll back*"
            lines << "(#{new_migrations} migrations, " \
              "#{new_post_deploy_migrations} post-deploy migrations)"
          end

          block.mrkdwn(text: lines.join(' '))
        end
      end

      private

      def new_migration?(diff)
        diff['new_path'].start_with?('db/migrate/') && diff['new_file']
      end

      def new_post_deploy_migration?(diff)
        diff['new_path'].start_with?('db/post_migrate/') && diff['new_file']
      end

      def timeout?
        @compare.compare_timeout
      end
    end
  end
end
