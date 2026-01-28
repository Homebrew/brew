# frozen_string_literal: true

require "livecheck/strategy/hackage"

RSpec.describe Homebrew::Livecheck::Strategy::Hackage do
  subject(:hackage) { described_class }

  let(:hackage_urls) do
    {
      package:   "https://hackage.haskell.org/package/abc-1.2.3/abc-1.2.3.tar.gz",
      downloads: "https://downloads.haskell.org/~abc/1.2.3/abc-1.2.3-src.tar.xz",
    }
  end
  let(:non_hackage_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:   "https://hackage.haskell.org/package/abc/src/",
      regex: %r{<h3>abc-(.*?)/?</h3>}i,
    }
  end

  describe "::match?" do
    it "returns true for a Hackage URL" do
      expect(hackage.match?(hackage_urls[:package])).to be true
      expect(hackage.match?(hackage_urls[:downloads])).to be true
    end

    it "returns false for a non-Hackage URL" do
      expect(hackage.match?(non_hackage_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a Hackage URL" do
      expect(hackage.generate_input_values(hackage_urls[:package])).to eq(generated)
      expect(hackage.generate_input_values(hackage_urls[:downloads])).to eq(generated)
    end

    it "returns an empty hash for a non-Hackage URL" do
      expect(hackage.generate_input_values(non_hackage_url)).to eq({})
    end
  end
end
