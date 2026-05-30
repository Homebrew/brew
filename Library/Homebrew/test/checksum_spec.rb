# typed: true
# frozen_string_literal: true

require "checksum"

RSpec.describe Checksum do
  let(:klass) { Checksum }

  describe "#empty?" do
    subject { klass.new("") }

    it { is_expected.to be_empty }
  end

  describe "#==" do
    subject(:checksum) { klass.new(TEST_SHA256) }

    let(:other) { klass.new(TEST_SHA256) }
    let(:other_reversed) { klass.new(TEST_SHA256.reverse) }

    specify(:aggregate_failures) do
      expect(checksum).to eq(other)
      expect(checksum).not_to eq(other_reversed)
      expect(checksum).not_to be_nil
    end
  end
end
