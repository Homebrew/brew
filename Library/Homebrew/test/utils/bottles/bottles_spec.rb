# frozen_string_literal: true

require "utils/bottles"

describe Utils::Bottles do
  describe "#tag", :needs_macos do
    it "returns :big_sur or :arm64_big_sur on Big Sur" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("11.0"))
      if Hardware::CPU.intel?
        expect(described_class.tag).to eq(:big_sur)
      else
        expect(described_class.tag).to eq(:arm64_big_sur)
      end
    end
  end
end
