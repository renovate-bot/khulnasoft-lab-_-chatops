# frozen_string_literal: true

module Chatops
  module Gitlab
    # A collection of feature flags.
    class FeatureCollection
      include Enumerable

      # token - The API token to use for retrieving the features.
      # match - When set to a String only the features including the substring
      #         will be returned.
      def initialize(token:, match: nil)
        @client = Client.new(token: token)
        @match = match
      end

      # Returns the feature for the given name, if any.
      def find_by_name(name)
        find { |feature| feature.name == name }
      end

      # Returns all the features grouped per state, sorted by the feature names.
      def per_state
        enabled = []
        disabled = []

        each do |feature|
          target = feature.enabled? ? enabled : disabled
          target << feature
        end

        [enabled.sort_by(&:name), disabled.sort_by(&:name)]
      end

      def each
        return to_enum(__method__) unless block_given?

        raw_features.each do |feature|
          next if @match && !feature.name.include?(@match)

          yield Feature.from_api_response(feature)
        end
      end

      #:nocov:
      def raw_features
        @client.features
      end
    end
  end
end
