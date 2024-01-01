# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy do
  subject(:strategy) { described_class }

  describe "::from_symbol" do
    it "returns the Strategy module represented by the Symbol argument" do
      expect(strategy.from_symbol(:page_match)).to eq(Homebrew::Livecheck::Strategy::PageMatch)
    end
  end

  describe "::from_url" do
    let(:url) { "https://sourceforge.net/projects/test" }

    context "when no regex is provided" do
      it "returns an array of usable strategies which doesn't include PageMatch" do
        expect(strategy.from_url(url)).to eq([Homebrew::Livecheck::Strategy::Sourceforge])
      end
    end

    context "when a regex is provided" do
      it "returns an array of usable strategies including PageMatch, sorted in descending order by priority" do
        expect(strategy.from_url(url, regex_provided: true))
          .to eq(
            [Homebrew::Livecheck::Strategy::Sourceforge, Homebrew::Livecheck::Strategy::PageMatch],
          )
      end
    end
  end

  describe "::handle_block_return" do
    it "returns an array of version strings when given a valid value" do
      expect(strategy.handle_block_return("1.2.3")).to eq(["1.2.3"])
      expect(strategy.handle_block_return(["1.2.3", "1.2.4"])).to eq(["1.2.3", "1.2.4"])
    end

    it "returns an empty array when given a nil value" do
      expect(strategy.handle_block_return(nil)).to eq([])
    end

    it "errors when given an invalid value" do
      expect { strategy.handle_block_return(123) }
        .to raise_error(TypeError, strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
