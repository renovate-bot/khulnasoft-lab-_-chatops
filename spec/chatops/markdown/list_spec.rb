# frozen_string_literal: true

describe Chatops::Markdown::List do
  describe '#to_s' do
    it 'formats an Array of values as a Markdown list' do
      list = described_class.new([10, 20, 30])

      expect(list.to_s).to eq("* 10\n* 20\n* 30")
    end
  end
end
