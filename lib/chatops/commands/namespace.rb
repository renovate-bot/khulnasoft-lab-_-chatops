# frozen_string_literal: true

module Chatops
  module Commands
    # Namespace class
    class Namespace
      include Command

      usage "#{command_name} [namespace id]"
      description 'Look up namespace information.'

      def perform
        namespace_id = arguments.join(' ')

        if namespace_id.empty?
          'You must supply a namespace ID to look up.'
        else
          namespace_info = Gitlab::Client
                           .new(token: gitlab_token)
                           .find_namespace(namespace_id)
        end

        if namespace_info
          submit_namespace_details(namespace_info)
        else
          namespace_not_found_error(namespace_id)
        end
      end
    end
  end
end
