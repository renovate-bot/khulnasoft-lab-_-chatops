# frozen_string_literal: true

module Chatops
  module Commands
    # Namespace class
    class Namespace
      include Command

      usage "#{command_name} [namespace id]"
      description 'Look up namespace information.'

      def perform
        namespace_id = arguments[1]
        return 'You must supply a namespace ID to look up.' unless namespace_id

        get_namespace(namespace_id)
      end

      def get_namespace(namespace_id)
        namespace_info = Gitlab::Client
          .new(token: gitlab_token)
          .find_namespace(namespace_id)

        if namespace_info
          submit_namespace_details(namespace_info)
        else
          namespace_not_found_error(namespace_id)
        end
      end

      def submit_namespace_details(namespace)
        Slack::Message
          .new(token: slack_token, channel: channel)
          .send(
            attachments: [
              {
                fields: [
                  {
                    title: 'ID',
                    value: namespace.id,
                    short: true
                  },
                  {
                    title: 'Name',
                    value: namespace.name,
                    short: true
                  },
                  {
                    title: 'Kind',
                    value: namespace.kind,
                    short: true
                  },
                  {
                    title: 'Path',
                    value: namespace.path,
                    short: true
                  }
                ]
              }
            ]
          )
      end

      def namespace_not_found_error(namespace_id)
        "No namespace could be found for the id #{namespace_id.inspect}."
      end
    end
  end
end
