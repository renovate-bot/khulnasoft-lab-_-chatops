# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Commands::Quality do
  let(:token) { '123' }
  let(:host) { 'gitlab.com' }
  let(:command_opts) { { filter: nil } }
  let(:command_envs) { { 'GITLAB_TOKEN' => token } }
  let(:client) { instance_double('Chatops::Gitlab::Client') }

  let(:schedule_yml) do
    <<~SCHEDULE
      ---
      - - 2022-10-03
        - Careem Ahamed
        - Will Meek
        - Tiffany Rea
      - - 2022-10-10
        - Carlo Catimbang
        - Alex Lyubenkov
        - Chloe Liu
    SCHEDULE
  end

  let(:issue_response) do
    [Gitlab::ObjectifiedHash.new(web_url: 'issue_1_url',
                                 title: 'issue_1_title',
                                 labels: %w[Incident::Mitigated Service::Logging]),
     Gitlab::ObjectifiedHash.new(web_url: 'issue_2_url',
                                 title: 'issue_2_title',
                                 labels: ['Incident::Active', 'Service::GitLab Rails'])]
  end

  describe '.available_subcommands' do
    it 'returns a Markdown list' do
      expect(described_class.available_subcommands(Chatops::Commands::Quality::COMMANDS)).to eq(<<~LIST.strip)
        * dri
      LIST
    end
  end

  describe '.dri' do
    let(:command) { described_class.new(command_args, command_opts, command_envs) }

    it 'requires a subcommand' do
      command = described_class.new(['dri'])

      response = command.perform

      expect(response).to match(/You must specify one of the available dri sub commands:/)

      Chatops::Commands::Quality::DRI_SUB_COMMANDS.each do |dri_sub_command|
        expect(response).to include(dri_sub_command)
      end
    end

    it 'requires a valid subcommand' do
      command = described_class.new(['abc'])

      response = command.perform

      expect(response).to match(/The feature subcommand is invalid. The following subcommands are available:/)
      expect(response).to include(described_class.examples)
    end

    shared_examples 'sub command' do |expected_response:|
      it 'returns the expected response' do
        expect(Chatops::Gitlab::Client)
          .to receive(:new)
          .with(token: token, host: host)
          .and_return(client)

        result =
          Timecop.freeze(Time.utc(2022, 10, 3)) do
            command.perform
          end

        expect(result.delete(' ').strip).to eq(expected_response)
      end
    end

    describe 'schedule' do
      let(:command_args) { %w[dri schedule] }

      before do
        allow(client)
          .to receive(:file_contents)
          .and_return(schedule_yml)
      end

      it_behaves_like 'sub command', expected_response: <<~DESC.delete(' ').strip
        ```
        +--------------+-----------------+----------------+-------------+
        |   Week of    | APAC            | EMEA           | AMER        |
        +--------------+-----------------+----------------+-------------+
        | =>2022-10-03 | Careem Ahamed   | Will Meek      | Tiffany Rea |
        |   2022-10-10 | Carlo Catimbang | Alex Lyubenkov | Chloe Liu   |
        +--------------+-----------------+----------------+-------------+
        ```
      DESC
    end

    describe 'schedule with filter' do
      let(:command_args) { %w[dri schedule] }
      let(:command_opts) { { filter: 'Will' } }

      before do
        allow(client)
          .to receive(:file_contents)
          .and_return(schedule_yml)
      end

      it_behaves_like 'sub command', expected_response: <<~DESC.delete(' ').strip
        ```
        +--------------+---------------+-----------+-------------+
        |   Week of    | APAC          | EMEA      | AMER        |
        +--------------+---------------+-----------+-------------+
        | =>2022-10-03 | Careem Ahamed | Will Meek | Tiffany Rea |
        +--------------+---------------+-----------+-------------+
        ```
      DESC
    end

    describe 'report' do
      let(:command_args) { %w[dri report] }

      before do
        allow(client)
          .to receive(:issues)
          .and_return(issue_response)
      end

      it_behaves_like 'sub command', expected_response: <<~DESC.delete(' ').strip
        \nCurrent week's report: <issue_1_url|issue_1_title>

        Last week's report: <issue_2_url|issue_2_title>
      DESC
    end

    describe 'incidents' do
      let(:command_args) { %w[dri incidents] }

      before do
        allow(client)
          .to receive(:issues)
          .and_return(issue_response)
      end

      it_behaves_like 'sub command', expected_response: <<~DESC.delete(' ').strip
        *  Mitigated |  Logging | <issue_1_url|issue_1_title>
        *  Active |  GitLab Rails | <issue_2_url|issue_2_title>
      DESC
    end
  end
end
