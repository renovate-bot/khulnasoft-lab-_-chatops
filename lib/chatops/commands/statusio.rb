# frozen_string_literal: true

module Chatops
  module Commands
    class Statusio
      include Command
      require 'pp'

      description 'Retrieve and update component status on status.gitlab.com.'

      # Error raised, when a string cannot be mapped to a code or vice versa
      UnknownCode = Class.new(StandardError)

      # All the available subcommands and the corresponding methods to invoke.
      COMMANDS = %w[list open resolve show update-component \
                    update-incident].freeze

      OPERATIONAL_STATUS = 100

      # https://kb.status.io/developers/status-codes/
      STATE_CODES = {
        100 => 'Investigating',
        200 => 'Identified',
        300 => 'Monitoring'
      }.freeze

      STATUS_CODES = {
        100 => 'Operational',
        300 => 'Degraded Performance',
        400 => 'Partial Service Disruption',
        500 => 'Service Disruption',
        600 => 'Security Event'
      }.freeze

      options do |o|
        o.bool '--all', 'flag all infrastructure as impacted'
        o.array '--component', 'component to include into update'
        o.array '--container', 'container to include into update'
        o.string '--details', 'message to attach to an action/incident'
        o.string '--state', 'state code or text to set'
        o.string '--status', 'status code or text to set'

        o.separator <<~HELP.chomp
          Available state codes:

          #{available_state_codes}

          Available status codes:

          #{available_status_codes}

          Available subcommands:

          #{available_subcommands}
        HELP
      end

      def self.available_subcommands
        Markdown::List.new(COMMANDS.sort).to_s
      end

      def self.available_state_codes
        codemap = []
        STATE_CODES.each { |k, v| codemap << "#{k}: #{v}" }

        Markdown::List.new(codemap).to_s
      end

      def self.available_status_codes
        codemap = []
        STATUS_CODES.each { |k, v| codemap << "#{k}: #{v}" }

        Markdown::List.new(codemap).to_s
      end

      def emoji_by_code(code)
        return ':white_check_mark:' if code <= 100
        return ':warning:' if code < 500

        ':x:'
      end

      def statusioclient
        @statusioclient ||= StatusioClient.new(
          ENV['STATUSIO_API_KEY'],
          ENV['STATUSIO_API_ID']
        )
      end

      def statuspage_id
        ENV['STATUSIO_PAGE_ID']
      end

      def notification_settings
        # Enable all the notification channels that are available
        #
        # This is put in a method so extension to support different
        # levels of notification is made easier down the road
        # 127 will set all required bits for all available channels
        # See https://github.com/statusio/statusio-ruby/blob/master/lib/statusio.rb#L21-L27
        # for more info
        127
      end

      def perform
        command = arguments[0]
        raise 'STATUSIO_API_KEY not set' if ENV['STATUSIO_API_KEY'].to_s.empty?
        raise 'STATUSIO_API_ID not set' if ENV['STATUSIO_API_ID'].to_s.empty?
        raise 'STATUSIO_PAGE_ID not set' if ENV['STATUSIO_PAGE_ID'].to_s.empty?

        if command.to_s.empty?
          public_send('show')
        elsif COMMANDS.include?(command)
          command.tr!('-', '_')
          public_send(command)
        else
          "Unknown command `#{command}`. Try `--help` for more info"
        end
      end

      def list
        incidents = statusioclient.incident_list_by_id statuspage_id
        active_incidents = incidents['result']['active_incidents']
        out = ''
        return 'No active incidents' if active_incidents.empty?

        active_incidents.each do |incident_id|
          incident = statusioclient.incident_single(
            statuspage_id,
            incident_id
          )
          out += render_incident incident['result'][0]
        end

        out
      end

      def validate_option_set(option)
        raise "#{option} needed" if options[option].to_s.empty?
      end

      def open
        affected_containers = []
        incident_name = arguments[1]
        validate_option_set :details
        validate_option_set :status
        validate_option_set :state
        affected_containers = selected_container_ids unless options[:all]

        incident_req = statusioclient.incident_create(
          statuspage_id,
          incident_name,
          options[:details],
          affected_containers,
          get_status_code(options[:status]),
          get_state_code(options[:state]),
          notification_settings,
          options[:all] && 1 || 0
        )

        stored_incident = statusioclient.incident_single(
          statuspage_id,
          incident_req['result']
        )
        render_incident stored_incident['result'][0]
      end

      def selected_container_ids
        affected_containers = []
        selected_components = []
        selected_containers = []

        options[:component].each do |option_component|
          selected_components += stausio_components.select do |component|
            component['name'].casecmp? option_component
          end
        end

        options[:container].each do |option_container|
          selected_components.each do |component|
            selected_containers = component['containers'].select do |container|
              container['name'].casecmp? option_container
            end
            selected_containers.each do |container|
              affected_containers.push "#{component['_id']}-#{container['_id']}"
            end
          end
        end

        raise 'combination of component and container does not yield a result' \
          if affected_containers.empty?

        affected_containers
      end

      def resolve
        incident_id = arguments[1]
        raise 'details needed' if options[:details].to_s.empty?

        statusioclient.incident_resolve(
          statuspage_id,
          incident_id,
          options[:details],
          OPERATIONAL_STATUS,
          OPERATIONAL_STATUS,
          notification_settings
        )

        "Resolved incident `#{incident_id}` with '#{options[:details]}'\n"
      end

      def show
        status = statusioclient.status_summary statuspage_id

        out = ''
        status['result']['status'].each do |component|
          out += " - #{emoji_by_code(component['status_code'])}"
          out += " `#{component['name']}`: `#{component['status']}`\n"
          component['containers'].each do |container|
            out += "   -  #{emoji_by_code(container['status_code'])}"
            out += " `#{container['name']}`: `#{container['status']}`\n"
          end
        end

        out
      end

      def update_component
        validate_option_set :status
        validate_option_set :details
        component_name = arguments[1]
        out = ''
        component = stausio_components.select do |s_component|
          s_component['name'].casecmp? component_name
        end[0]

        component['containers'].each do |container|
          next unless selected_container? container

          statusioclient.component_status_update(
            statuspage_id,
            component['_id'],
            container['_id'],
            options[:details],
            get_status_code(options[:status])
          )

          out += "Updated `#{component['name']}` / `#{container['name']}` to"
          out += " status `#{get_status_string(options[:status])}`\n"
        end

        out
      end

      def selected_container?(container)
        return true if options[:container].empty?

        # In case we don't want to update every container: Filter them
        options[:container].select do |opt_container|
          container['name'].casecmp? opt_container
        end.positive?
      end

      def update_incident
        incident_id = arguments[1]
        validate_option_set :details
        validate_option_set :status
        validate_option_set :state

        statusioclient.incident_update(
          statuspage_id,
          incident_id,
          options[:details],
          get_status_code(options[:status]),
          get_state_code(options[:state]),
          notification_settings
        )

        out = "Updated incident `#{incident_id}` to state"
        out += " `#{get_state_string(options[:state])}`\n"
        out
      end

      # Normalizes a state code or state string into a valid string
      def get_state_string(input)
        return STATE_CODES[input.to_i] if STATE_CODES.key? input.to_i

        STATE_CODES.each do |_, state|
          return state if state.casecmp? input
        end
        raise UnknownCode, "No such state `#{input}`"
      end

      # Normalizes a state code or state string into a valid code
      def get_state_code(input)
        return input.to_i if STATE_CODES.key? input.to_i

        STATE_CODES.each do |code, state|
          return code if state.casecmp? input
        end
        raise UnknownCode, "No such state `#{input}`"
      end

      # Normalizes a status code or status string into a valid string
      def get_status_string(input)
        return STATUS_CODES[input.to_i] if STATUS_CODES.key? input.to_i

        STATUS_CODES.each do |_, status|
          return status if status.casecmp? input
        end
        raise UnknownCode, "No such status `#{input}`"
      end

      # Normalizes a status code or status string into a valid code
      def get_status_code(input)
        return input.to_i if STATUS_CODES.key? input.to_i

        STATUS_CODES.each do |code, status|
          return code if status.casecmp? input
        end
        raise UnknownCode, "No such status `#{input}`"
      end

      # A cached way to retrieve all components and containers therein
      def stausio_components
        @components ||= statusioclient.component_list statuspage_id
        @components['result']
      end

      # Renders a markdown representation of the provided incident
      def render_incident(incident)
        out = ''
        out += " - #{incident['name']} (`#{incident['_id']}`):"
        out += " `#{get_state_string incident['messages'].last['state']}`\n"
        out += "   - Messages\n"
        incident['messages'].each do |message|
          out += "     - #{message['datetime']}: #{message['details']}\n"
        end
        out += "   - Affected services\n"
        incident['components_affected'].each do |affected_component|
          out += render_incident_component incident, affected_component
        end

        out
      end

      def render_incident_component(incident, affected_component)
        out = "     - `#{affected_component['name']}`\n"
        full_affected_component = stausio_components.select do |component|
          component['_id'] == affected_component['_id']
        end[0]

        incident['containers_affected'].each do |affected_container|
          affected = full_affected_component['containers'].select do |cont|
            cont['_id'] == affected_container['_id']
          end[0]
          out += "       - `#{affected['name']}`\n"
        end

        out
      end
    end
  end
end
