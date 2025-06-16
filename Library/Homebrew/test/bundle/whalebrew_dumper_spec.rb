# frozen_string_literal: true

require "bundle"
require "bundle/whalebrew_dumper"

RSpec.describe Homebrew::Bundle::WhalebrewDumper do
  subject(:dumper) { described_class }

  context "when whalebrew is not installed" do
    before do
      dumper.reset!
      allow(Homebrew::Bundle).to receive(:whalebrew_installed?).and_return(false)
    end

    it "returns empty list" do
      expect(dumper.images).to be_empty
    end

    it "dumps as empty string" do
      expect(dumper.dump).to eql("")
    end
  end

  context "when whalebrew is installed" do
    before do
      allow(Homebrew::Bundle).to receive(:whalebrew_installed?).and_return(true)
      allow(dumper).to receive(:images).and_return(["whalebrew/wget", "whalebrew/dig"])
    end

    context "when images are installed" do
      let(:expected_whalebrew_dump) do
        %Q(whalebrew "whalebrew/wget"\nwhalebrew "whalebrew/dig")
      end

      it "returns correct listing" do
        expect(dumper.images).to eq(["whalebrew/wget", "whalebrew/dig"])
      end

      it "dumps usable output for Brewfile" do
        expect(dumper.dump).to eql(expected_whalebrew_dump)
      end
    end
  end
end
