# frozen_string_literal: true

require "checksum"

RSpec.describe Checksum do
  describe "#empty?" do
    subject { described_class.new("") }

    it { is_expected.to be_empty }
  end

  describe "#==" do
    subject { described_class.new(TEST_SHA256) }

    let(:other) { described_class.new(TEST_SHA256) }
    let(:other_reversed) { described_class.new(TEST_SHA256.reverse) }

    specify(:aggregate_failures) do
      expect(subject).to eq(other) # rubocop:todo RSpec/NamedSubject
      expect(subject).not_to eq(other_reversed) # rubocop:todo RSpec/NamedSubject
      expect(subject).not_to be_nil # rubocop:todo RSpec/NamedSubject
    end
  end
end
