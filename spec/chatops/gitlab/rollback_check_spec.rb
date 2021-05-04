# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Gitlab::RollbackCheck do
  it 'considers a diff with migrations as safe' do
    compare = instance_double(
      'comparison',
      diffs: [
        { 'new_path' => 'db/migrate/foo.rb', 'new_file' => true },
        { 'new_path' => 'db/migrate/bar.rb', 'new_file' => false }
      ],
      compare_timeout: false
    )

    check = described_class.new(compare, nil).execute

    expect(check).to be_safe
    expect(check.new_migrations.size).to eq(1)
    expect(check.new_post_deploy_migrations.size).to eq(0)
  end

  it 'considers a diff with post-deploy migrations as unsafe' do
    compare = instance_double(
      'comparison',
      diffs: [
        { 'new_path' => 'db/post_migrate/foo.rb', 'new_file' => true },
        { 'new_path' => 'db/post_migrate/bar.rb', 'new_file' => false }
      ],
      compare_timeout: false
    )

    check = described_class.new(compare, nil).execute

    expect(check).not_to be_safe
    expect(check.new_migrations.size).to eq(0)
    expect(check.new_post_deploy_migrations.size).to eq(1)
  end

  it 'considers a compare timeout as unsafe' do
    compare = instance_double(
      'comparison',
      diffs: [
        { 'new_path' => 'README.md', 'new_file' => true },
        { 'new_path' => 'db/post_migrate/bar.rb', 'new_file' => false }
      ],
      compare_timeout: true
    )

    check = described_class.new(compare, nil).execute

    expect(check).not_to be_safe
    expect(check.new_migrations.size).to eq(0)
    expect(check.new_post_deploy_migrations.size).to eq(0)
  end

  it 'considers a diff otherwise safe' do
    compare = instance_double(
      'comparison',
      diffs: [
        { 'new_path' => 'README.md', 'new_file' => true },
        { 'new_path' => 'db/migrate/foo.rb', 'new_file' => false }
      ],
      compare_timeout: false
    )

    check = described_class.new(compare, nil).execute

    expect(check).to be_safe
  end
end
