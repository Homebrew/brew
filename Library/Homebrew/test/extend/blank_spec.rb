# frozen_string_literal: true

require "extend/blank"

RSpec.describe Object do
  let(:empty_true) do
    Class.new(described_class) do
      # This API is intentionally non-ideal for testing.
      # rubocop:disable Naming/PredicateMethod
      def empty?
        0
      end
      # rubocop:enable Naming/PredicateMethod
    end
  end
  let(:empty_false) do
    Class.new(described_class) do
      def empty?
        false
      end
    end
  end
  let(:blank) { [empty_true.new, nil, false, "", "   ", "  \n\t  \r ", "　", "\u00a0", [], {}] }
  let(:present) { [empty_false.new, described_class.new, true, 0, 1, "a", [nil], { nil => 0 }, Time.now] }

  describe ".blank?" do
    it "checks if an object is blank" do
      blank.each { |v| expect(v.blank?).to be true }
      present.each { |v| expect(v.blank?).to be false }
    end

    it "checks if an object is blank with bundled string encodings" do
      Encoding.list.reject(&:dummy?).each do |encoding|
        expect(" ".encode(encoding).blank?).to be true
        expect("a".encode(encoding).blank?).to be false
      end
    end
  end

  describe ".present?" do
    it "checks if an object is present" do
      blank.each { |v| expect(v.present?).to be false }
      present.each { |v| expect(v.present?).to be true }
    end
  end

  describe ".presence" do
    it "returns the object if present, or nil" do
      blank.each { |v| expect(v.presence).to be_nil }
      present.each { |v| expect(v.presence).to be v }
    end
  end
end
