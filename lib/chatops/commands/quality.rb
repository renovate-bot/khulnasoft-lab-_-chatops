# frozen_string_literal: true

require 'yaml'
require 'tty-table'

module Chatops
  module Commands
    # Shows information about the available commands.
    class Quality
      include Command

      description 'Perform quality related tasks'

      PIPELINE_TRIAGE_PROJECT_ID = '15291320'
      INFRA_TEAM_PROD_PROJECT_ID = '7444821'
      DRI_SCHEDULE_FILE_NAME = 'new_dri_schedule.yml'

      # All the available subcommands that can be invoked.
      COMMANDS = Set.new(%w[dri])
      DRI_SUB_COMMANDS = Set.new(%w[schedule report incidents])

      options do |o|
        o.string(
          '-f', '--filter',
          'Only display data with the filter value'
        )

        o.separator(<<~SCHEDULE)

          Available subcommands:

          #{available_subcommands(COMMANDS)}

          Some examples:

          #{Quality.examples}
        SCHEDULE
      end

      def self.available_subcommands(com)
        Markdown::List.new(com.to_a.sort).to_s
      end

      def self.examples
        <<~EX.strip
          # List the entire DRI schedule:
          quality dri schedule

          # Show the DRI schedule filtered by a keyword:
          quality dri schedule --filter john

          # Show the DRI pipeline triage reports:
          quality dri report

          # Show current incidents:
          quality dri incidents
        EX
      end

      def perform
        command = arguments[0]

        if COMMANDS.include?(command)
          public_send(command)
        else
          unsupported_command
        end
      end

      def dri
        dri_sub_command = arguments[1]

        if dri_sub_command && DRI_SUB_COMMANDS.include?(dri_sub_command)
          public_send(dri_sub_command)
        else
          <<~MSG
            You must specify one of the available dri sub commands:
            #{Quality.available_subcommands(DRI_SUB_COMMANDS)}
          MSG
        end
      end

      # rubocop:disable Metrics/AbcSize
      def schedule
        content = [].tap do |rows|
          dri_schedule_yaml_data.each do |row|
            row_hash = {}
            current_week = (Date.today - Date.today.wday + 1).to_s

            week_of = row[0].to_s == current_week ? "=>#{row[0]}" : row[0].to_s
            row_hash['AMER'] = row[1]
            row_hash['EMEA'] = row[2]
            row_hash['APAC'] = row[3]

            row_data = [week_of, row[1], row[2], row[3]]
            next if options[:filter] && row_data.none? { |s| s.downcase.include?(options[:filter].downcase) }

            rows << row_data
          end
        end

        Markdown::Code.new(TTY::Table.new(schedule_headers, content).render(:ascii, padding: [0, 1])).to_s
      end
      # rubocop:enable Metrics/AbcSize

      def incidents
        response = client.issues(INFRA_TEAM_PROD_PROJECT_ID,
                                 order_by: 'updated_at',
                                 state: 'opened',
                                 labels: 'incident')

        incidents_arr = []

        response.each do |incident|
          status = 'N/A'
          service = 'N/A'

          incident.labels.each do |label|
            status = label.gsub('Incident::', ' ').to_s if label.include?('Incident::')
            service = label.gsub('Service::', ' ').to_s if label.include?('Service::')
          end

          incidents_arr << "#{status} | #{service} | <#{incident.web_url}|#{incident.title}>"
        end

        "\n" + Markdown::List.new(incidents_arr).to_s
      end

      def report
        issues = client.issues(PIPELINE_TRIAGE_PROJECT_ID)

        <<~DESC
          \nCurrent week's report: <#{issues[0].web_url}|#{issues[0].title}>

          Last week's report: <#{issues[1].web_url}|#{issues[1].title}>
        DESC
      end

      private

      def client
        @client ||= Gitlab::Client.new(
          token: gitlab_token,
          host: 'gitlab.com'
        )
      end

      def dri_schedule_yaml_data
        @dri_schedule_yaml_data ||=
          YAML.safe_load(client.file_contents(PIPELINE_TRIAGE_PROJECT_ID, DRI_SCHEDULE_FILE_NAME), [Date])
      end

      def unsupported_command
        vals = COMMANDS.to_a.sort.map { |name| Markdown::Code.new(name) }
        list = Markdown::List.new(vals)

        <<~MESSAGE.strip
          The feature subcommand is invalid. The following subcommands are available:

          #{list}

          Some examples:

          ```
          #{Quality.examples}
          ```

          For more information run `quality --help`.
        MESSAGE
      end

      def schedule_headers
        ['Week of', 'APAC', 'EMEA', 'AMER']
      end
    end
  end
end
