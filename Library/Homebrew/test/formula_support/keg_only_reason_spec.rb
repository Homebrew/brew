# frozen_string_literal: true

require "formula_support"

describe KegOnlyReason do
  describe "#to_s" do
    it "returns the reason provided" do
      r = described_class.new :provided_by_macos, "test"
      expect(r.to_s).to eq("test")
    end

    it "returns a default message when no reason is provided" do
      r = described_class.new :provided_by_macos, ""
      expect(r.to_s).to match(/^macOS already provides/)
    end
  end
end
