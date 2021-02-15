# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Events::Client do
  let(:client_with_auth) { instance_double('client_with_auth') }
  let(:client) do
    instance_double(
      'client',
      basic_auth: client_with_auth
    )
  end

  describe '#send_event' do
    before do
      allow(HTTP).to receive(:headers).and_return(client)
    end

    around do |ex|
      ClimateControl.modify(
        CI_JOB_NAME: 'some_job',
        ES_NONPROD_EVENT_PASS: '1234',
        ES_NONPROD_URL: 'http://example.com:9243',
        GITLAB_USER_LOGIN: 'some_user'
      ) do
        Timecop.freeze(Time.utc(2020, 12, 5)) { ex.run }
      end
    end

    it 'sends a notification with fields set' do
      client = described_class.new('gprd')
      expect(client_with_auth).to receive(:post)
        .with(
          'http://example.com:9243/events-gprd/_doc',
          json: {
            'env' => 'gprd',
            'message' => 'some event',
            'source' => 'some_job',
            'stage' => 'main',
            'time' => '2020-12-05T00:00:00Z',
            'some_field' => '100',
            'username' => 'some_user'
          }
        )
      client.send_event(
        'some event',
        fields: {
          'some_field' => '100'
        }
      )
    end

    it 'sends a notification for the gprd environment' do
      client = described_class.new('gprd')
      expect(client_with_auth).to receive(:post)
        .with(
          'http://example.com:9243/events-gprd/_doc',
          json: {
            'env' => 'gprd',
            'message' => 'some event',
            'source' => 'some_job',
            'stage' => 'main',
            'time' => '2020-12-05T00:00:00Z',
            'username' => 'some_user'
          }
        )
      client.send_event('some event')
    end

    it 'sends a notification for the gstg environment' do
      client = described_class.new('gstg')
      expect(client_with_auth).to receive(:post)
        .with(
          'http://example.com:9243/events-gstg/_doc',
          json: {
            'env' => 'gstg',
            'message' => 'some event',
            'source' => 'some_job',
            'stage' => 'main',
            'time' => '2020-12-05T00:00:00Z',
            'username' => 'some_user'
          }
        )
      client.send_event('some event')
    end

    it 'fails for an invalid env' do
      expect { described_class.new('some-invalid-env') }
        .to raise_error(
          RuntimeError,
          'Only gstg,gprd are valid envs for sending events, ' \
          "got 'some-invalid-env'."
        )
    end
  end
end
