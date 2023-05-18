# frozen_string_literal: true

module Chatops
  class MergeRequestURLParser
    MR_URL_REGEX = %r{https://gitlab.com/(?<project>.+)/-/merge_requests/(?<iid>\d+)}

    attr_reader :mr_url

    def initialize(mr_url)
      @mr_url = mr_url
    end

    def valid?
      !mr_url_parts.nil?
    end

    def merge_request_project
      mr_url_parts[:project]
    end

    def merge_request_iid
      mr_url_parts[:iid]
    end

    private

    def mr_url_parts
      @mr_url_parts ||= MR_URL_REGEX.match(mr_url)
    end
  end
end
