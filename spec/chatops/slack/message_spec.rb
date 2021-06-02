# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Slack::Message do
  describe '#send' do
    context 'when the message is valid' do
      it 'sends a message to Slack' do
        response = instance_double('response', body: JSON.dump(ok: true))

        expect(HTTP)
          .to receive(:post)
          .with(
            described_class::API_URL,
            headers: {
              accept: 'application/json',
              content_type: 'application/json',
              authorization: 'Bearer 123'
            },
            body: {
              channel: 'foo',
              response_type: :in_channel,
              as_user: true,
              text: 'hello',
              attachments: %w[foo],
              blocks: %w[bar],
              unfurl_links: false,
              unfurl_media: false
            }.to_json
          )
          .and_return(response)

        described_class
          .new(token: '123', channel: 'foo')
          .send(text: 'hello', attachments: %w[foo], blocks: %w[bar])
      end
    end

    context 'when Slack responds with an error' do
      it 'raises MessageError' do
        response = instance_double(
          'response',
          body: JSON.dump(ok: false, error: 'kittens')
        )

        expect(HTTP)
          .to receive(:post)
          .and_return(response)

        message = described_class.new(token: '123', channel: 'foo')

        expect { message.send }
          .to raise_error(described_class::MessageError, 'kittens')
      end
    end
  end
end
