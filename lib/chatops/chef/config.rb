# frozen_string_literal: true

module Chatops
  module Chef
    module Config
      DEFAULT_CHEF_URL = 'https://chef.gitlab.com/organizations/gitlab'

      # Chef pem for authenticating with the Chef server
      def chef_pem_key
        env.fetch('CHEF_PEM_KEY')
      end

      # Chef username for interacting with the chef server
      def chef_username
        env.fetch('CHEF_USERNAME')
      end

      # Chef endpoint, defaults to GitLab's chef server
      def chef_url
        env.fetch('CHEF_URL', DEFAULT_CHEF_URL)
      end
    end
  end
end
