# frozen_string_literal: true

module Chatops
  module Slack
    # A FileUpload can be used to upload a file to a Slack channel.
    class FileUpload
      # The URL to upload files to.
      UPLOAD_URL = 'https://slack.com/api/files.upload'

      # Error raised when a file could not be uploaded.
      UploadError = Class.new(StandardError)

      # file - The file object to upload (e.g. a Tempfile or a String).
      # type - The Slack file type of the file to upload (e.g. `:png`).
      # channel - The channel ID to upload the file to.
      # token - The API token to use for uploading the file.
      # title - The title of the upload.
      # comment - A comment to add to the file.
      def initialize(file:, type:, channel:, token:, title: nil, comment: nil)
        @file = file
        @type = type
        @title = title
        @token = token
        @channel = channel
        @comment = comment
      end

      def upload
        response = HTTP.post(
          UPLOAD_URL,
          form: {
            token: @token,
            channels: @channel,
            filetype: @type,
            title: @title,
            initial_comment: @comment
          }.merge(file_parameters)
        )

        return if response.status == 200 && JSON.parse(response.body)['ok']

        raise UploadError, 'The file could not be uploaded to Slack'
      end

      def file_parameters
        if @file.is_a?(String)
          { content: @file }
        else
          {
            file: HTTP::FormData::File.new(@file.path),
            filename: File.basename(@file.path)
          }
        end
      end
    end
  end
end
