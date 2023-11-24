# frozen_string_literal: true

# Helpers for working with the `gitlab` client gem
module GitlabHelper
  # Simulate a `Gitlab::Error::Error` class
  #
  # klass   - Gitlab::Error::Error class object, or a Symbol of an Error class
  # code    - Status code (default: 500)
  # message - Status message: (default: 'Something went wrong')
  def gitlab_error(klass, code: 500, message: 'Something went wrong')
    error = double(
      response: double(
        code: code
      ),
      parsed_response: double(
        message: message
      )
    ).as_null_object

    if klass.is_a?(Gitlab::Error::Error)
      klass.new(error)
    else
      Object.const_get("Gitlab::Error::#{klass}").new(error)
    end
  end
end

RSpec.configure do |config|
  config.include GitlabHelper
end
