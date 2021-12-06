# frozen_string_literal: true

module Chatops
  module Gitlab
    # Class for storing and formatting information about a feature flag.
    class Feature
      attr_reader :name, :gates

      # Returns a new Feature based on a raw feature object returned by the API.
      def self.from_api_response(feature)
        new(
          name: feature.name,
          state: feature.state,
          gates: feature.gates,
          definitions: feature.definition
        )
      end

      # Returns `true` if the given value is a valid feature value.
      def self.valid_value?(value)
        case value
        when 'true', 'false', '0'..'100'
          true
        else
          false
        end
      end

      # name - The name of the feature flag.
      # state - The state of the feature such as "on" or "conditional".
      # gates - The list of feature gates for this flag.
      def initialize(name:, state:, gates: [], definitions: nil)
        @name = name
        @state = state
        @gates = gates
        @definitions = definitions
      end

      # Returns `true` if the feature is enabled.
      def enabled?
        @state == 'on' ||
          (@state == 'conditional' && percentage_of_time.positive?)
      end

      def state_label
        enabled? ? 'Enabled' : 'Disabled'
      end

      # Returns the percentage of time this feature is enabled.
      def percentage_of_time
        gate = @gates.find { |g| g['key'] == 'percentage_of_time' }

        gate ? gate['value'] : 100
      end

      # Returns a Hash that can be used as a Slack attachment field.
      def to_attachment_field
        percent = percentage_of_time
        value = "Percentage of time: #{percent}%" if percent < 100

        {
          title: name,
          value: value,
          short: true
        }
      end

      def attachment_fields_for_gates
        @gates.map do |gate|
          {
            title: gate_key_title(gate['key']),
            value: Markdown::Code.new(gate['value'].to_s).to_s,
            short: true
          }
        end
      end

      private

      def gate_key_title(gate_key)
        case gate_key
        when 'boolean'
          'Enabled Globally'
        when 'actors'
          'Scoped to'
        else
          gate_key
        end
      end
    end
  end
end
