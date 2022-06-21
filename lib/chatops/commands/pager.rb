# frozen_string_literal: true

# Invocation examples
#
# CHAT_INPUT='pause --environment=test' bundle exec ./bin/chatops pager
# CHAT_INPUT='resume --environment=test' bundle exec ./bin/chatops pager
#
# CHAT_INPUT='pause' bundle exec ./bin/chatops pager
# CHAT_INPUT='resume' bundle exec ./bin/chatops pager
#

require 'chronic'
require 'time'

module Chatops
  module Commands
    class Pager
      include Command
      DEFAULTS = {
        filter_by_creator: false,
        environment: :production,
        duration: '1 hour'
      }.freeze
      SERVICES = {
        production: [
          'GitLab Production',
          'Production Database',
          'SLO Alerts gprd main stage'
        ],
        staging: [
          'GitLab Staging'
        ],
        test: [
          'nnelson-test'
        ]
      }.freeze
      MESSAGES = {
        pages_paused_for_user_pattern: 'Chatops has paused pages for user %<username>s$',
        paused_already: 'Cannot proceed -- existing maintenance window ' \
          'in effect until: %<end_time>s',
        window_not_found: 'Cannot proceed -- there are no active ' \
          'maintenance windows being managed by GitLab Chatops',
        reason: 'Chatops has paused pages for user %<username>s'
      }.freeze

      options do |parse|
        parse.string(
          '--duration',
          "Duration of window; default: #{DEFAULTS[:duration]}",
          default: DEFAULTS[:duration]
        )
        parse.string(
          '--environment',
          "Environment [#{SERVICES.keys.join(',')}]; default: #{DEFAULTS[:environment]}",
          default: DEFAULTS[:environment]
        )
        parse.bool(
          '--filter-by-creator',
          "Filter maintenance windows by creator; default: #{DEFAULTS[:filter_by_creator]}",
          default: DEFAULTS[:filter_by_creator]
        )
      end

      usage "#{command_name} <pause|resume> [options]"
      description 'Pause or resume pages.'

      def perform
        action = arguments.shift

        case action.to_sym
        when :pause then pause
        when :resume then resume
        else respond("Invalid command.\n\n`Usage: #{Pager.usage}`")
        end
      end

      private

      def client
        @client ||= Chatops::PagerDuty::ExtendedClient.new(pagerduty_token)
      end

      def respond(message)
        Slack::Message.new(token: slack_token, channel: channel)
          .send(text: message)
      end

      def build_notice(notice, services)
        attachments = [
          { pretext: notice, fallback: notice }
        ]

        services.each do |service|
          attachments << { text: "`#{service}`", fallback: service }
        end

        attachments
      end

      def notice(attachments)
        Slack::Message.new(token: slack_token, channel: channel)
          .send(attachments: attachments)
      end

      def username
        env.fetch('GITLAB_USER_LOGIN', nil)
      end

      def start_time
        Time.now
      end

      def pause
        services = get_services_by_environment
        return if already_paused?(services)

        end_time = parse_duration
        reason = format(MESSAGES[:reason], username: username)
        window = nil
        begin
          window = client.start_maintenance_window(services, start_time, end_time, reason)
        rescue Chatops::PagerDuty::ExtendedClient::Error => e
          respond("Fatal: #{e.message}")
          puts "Fatal: #{e.message}"
          exit(1)
        rescue StandardError => e
          respond("Unexpected error: #{e.message}")
          puts "Unexpected error: #{e.message}"
          e.backtrace.each { |t| puts t }
          exit(1)
        end
        notice(build_notice('Pages paused (maintenance window started) ' \
          'for services:', services_names(window['services'])))
        nil
      end

      # rubocop: disable  Metrics/AbcSize
      def resume
        services = get_services_by_environment
        windows = get_windows_by_services(services)
        windows = get_active_windows(windows)
        windows = filter_windows_by_creator(username, windows) if options[:filter_by_creator]
        return respond(MESSAGES[:window_not_found]) if windows.empty?

        windows.each do |window|
          updated_window = nil
          begin
            updated_window = client.terminate_maintenance_window(window)
          rescue Chatops::PagerDuty::ExtendedClient::Error => e
            respond("Fatal: #{e.message}")
            puts "Fatal: #{e.message}"
            exit(1)
          rescue StandardError => e
            respond("Unexpected error: #{e.message}")
            puts "Unexpected error: #{e.message}"
            e.backtrace.each { |t| puts t }
            exit(1)
          end
          notice(build_notice('Pager resumed (maintenance window ended) ' \
            'for services:', services_names(updated_window['services'])))
        end
        nil
      end
      # rubocop: enable  Metrics/AbcSize

      def get_services_by_environment(environment = options[:environment])
        service_selection = SERVICES[environment.to_s.to_sym]
        client.services.select { |service| service_selection&.include?(service['name']) }
      end

      def get_windows_by_services(services, windows = client.maintenance_windows)
        service_names = services_names(services)
        windows.select do |window|
          window['services'].map { |service| service['summary'] }.sort == service_names && \
            Time.parse(window['end_time']) > Time.now
        end
      end

      def get_active_windows(windows = client.maintenance_windows)
        windows.select do |window|
          Time.parse(window['end_time']) > Time.now
        end
      end

      def filter_windows_by_creator(creator, windows = client.maintenance_windows)
        pattern = Regexp.new(format(MESSAGES[:pages_paused_for_user_pattern], username: creator))
        windows.select { |window| pattern.match?(window['description']) }
      end

      def services_names(services)
        services.map { |service| service['name'] || service['summary'] }.sort
      end

      def already_paused?(services)
        windows = get_windows_by_services(services)
        windows = filter_windows_by_creator(username, windows) if options[:filter_by_creator]

        return false if windows.empty?

        respond(format(MESSAGES[:paused_already], end_time: windows.first['end_time']))
        true
      end

      def parse_duration
        Chronic.parse("#{options[:duration]} from now")
      end
    end
    # class Pager
  end
  # module Commands
end
# module Chatops

module Chatops
  module PagerDuty
    module MaintenanceWindowClientExtensions
      ENDPOINT = Chatops::PagerDuty::Client::ENDPOINT

      def services(query = nil)
        params = query ? { query: query } : {}
        url = [ENDPOINT, :services].join('/')
        params[:total] = true

        services = []
        loop do
          response = client.get(url, params: params)
          result = JSON.parse(response.body)
          services.concat(result.fetch('services', []))
          break unless result['more']

          params[:offset] = services.length
        end
        services
      end

      def maintenance_windows(query = nil)
        params = query ? { query: query } : {}
        url = [ENDPOINT, :maintenance_windows].join('/')
        params[:total] = true

        windows = []
        loop do
          response = client.get(url, params: params)
          result = JSON.parse(response.body)
          windows.concat(result.fetch('maintenance_windows', []))
          break unless result['more']

          params[:offset] = windows.length
        end
        windows
      end

      def start_maintenance_window(services, start_time, end_time, reason)
        url = [ENDPOINT, :maintenance_windows].join('/')
        services_references = services.map do |service|
          { id: service['id'], type: 'service_reference' }
        end
        body = {
          maintenance_window: {
            services: services_references,
            start_time: start_time,
            end_time: end_time,
            description: reason
          }
        }
        response = client.post(url, body: body.to_json)
        result = JSON.parse(response.body)
        if result.key?('error')
          service_names = services.map { |service| "`#{service['summary']}`" }.join(', ')
          msg = "Failed #{service_names} maintenance window creation: #{result['error']['message']}"
          raise ExtendedClient::Error, msg
        end
        raise ExtendedClient::Error, result['error']['message'] if result.key?('error')

        result.fetch('maintenance_window', {})
      end

      def terminate_maintenance_window(window)
        url = [ENDPOINT, :maintenance_windows, window['id']].join('/')
        body = {
          maintenance_window: {
            type: 'maintenance_window',
            id: window['id'],
            end_time: Time.now
          }
        }
        response = client.put(url, body: body.to_json)
        result = JSON.parse(response.body)
        if result.key?('error')
          service_names = window['services'].map { |service| "`#{service['summary']}`" }.join(', ')
          msg = "Failed #{service_names} maintenance window update: #{result['error']['message']}"
          raise ExtendedClient::Error, msg
        end

        result.fetch('maintenance_window', {})
      end
    end
    # module MaintenanceWindowClientExtensions

    class ExtendedClient < Chatops::PagerDuty::Client
      Error = Class.new(StandardError)
      include Chatops::PagerDuty::MaintenanceWindowClientExtensions
    end
  end
  # module PagerDuty
end
# module Chatops
