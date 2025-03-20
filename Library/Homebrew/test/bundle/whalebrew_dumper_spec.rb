# frozen_string_literal: true

require "bundle"

RSpec.describe Homebrew::Bundle::WhalebrewDumper do
  subject(:dumper) { described_class }

  describe ".images" do
    before do
      dumper.reset!
      allow(Homebrew::Bundle).to receive(:whalebrew_installed?).and_return(true)
    end

    let(:whalebrew_list_single_output) do
      "COMMAND   IMAGE\nwget      whalebrew/wget"
    end

    let(:whalebrew_list_duplicate_output) do
      "COMMAND   IMAGE\nwget      whalebrew/wget\nwget      whalebrew/wget"
    end

    it "removes the header" do
      allow(dumper).to receive(:`).with("whalebrew list 2>/dev/null")
                                  .and_return(whalebrew_list_single_output)
      expect(dumper.images).not_to include("COMMAND")
      expect(dumper.images).not_to include("IMAGE")
    end

    it "dedupes items" do
      allow(dumper).to receive(:`).with("whalebrew list 2>/dev/null")
                                  .and_return(whalebrew_list_duplicate_output)
      expect(dumper.images).to eq(["whalebrew/wget"])
    end
  end

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
