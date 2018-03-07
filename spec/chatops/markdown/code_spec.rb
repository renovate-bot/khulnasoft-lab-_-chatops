# frozen_string_literal: true

require 'spec_helper'

describe Chatops::Markdown::Code do
  describe '#to_s' do
    it 'formats a single line as a Markdown code block' do
      code = described_class.new('hello').to_s

      expect(code).to eq('`hello`')
    end

    it 'formats a multi-line string as Markdown code block' do
      code = described_class.new("hello\nworld").to_s

      expect(code).to eq("```\nhello\nworld\n```")
    end

    it 'removes leading and trailing whitespace from the input value' do
      code = described_class.new(' hello ').to_s

      expect(code).to eq('`hello`')
    end
  end
end
