# frozen_string_literal: true

require 'spec_helper'

describe Chatops::PagerDuty::Client do
  subject(:client) do
    described_class.new(ENV.fetch('PAGERDUTY_TOKEN', 'fake_token'))
  end

  describe '#services' do
    it 'gets a list of services' do
      VCR.use_cassette('pager_duty/services_all') do
        services = client.services

        expect(services.size).to eq(25)
      end
    end

    it 'gets a list of services matching a query' do
      VCR.use_cassette('pager_duty/services_query') do
        services = client.services('culpa')

        expect(services.size).to eq(5)
        expect(services).to be_all do |s|
          s['name'].include?('culpa')
        end
      end
    end
  end

  describe '#oncalls' do
    it 'gets a list of oncalls, including user data' do
      VCR.use_cassette('pager_duty/oncalls') do
        oncalls = client.oncalls

        expect(oncalls.size).to eq(25)
        expect(oncalls.first).to have_key('user')
      end
    end
  end
end
