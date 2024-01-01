# frozen_string_literal: true

require "checksum"

describe Checksum do
  describe "#empty?" do
    subject { described_class.new("") }

    it { is_expected.to be_empty }
  end

  describe "#==" do
    subject { described_class.new(TEST_SHA256) }

    let(:other) { described_class.new(TEST_SHA256) }
    let(:other_reversed) { described_class.new(TEST_SHA256.reverse) }

    it { is_expected.to eq(other) }
    it { is_expected.not_to eq(other_reversed) }
    it { is_expected.not_to be_nil }
  end
end
