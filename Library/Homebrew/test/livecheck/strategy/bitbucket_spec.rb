# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Bitbucket do
  subject(:bitbucket) { described_class }

  let(:bitbucket_urls) do
    {
      get:       "https://bitbucket.org/abc/def/get/1.2.3.tar.gz",
      downloads: "https://bitbucket.org/abc/def/downloads/ghi-1.2.3.tar.gz",
    }
  end
  let(:non_bitbucket_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      get:       {
        url:   "https://bitbucket.org/abc/def/downloads/?tab=tags",
        regex: /<td[^>]*?class="name"[^>]*?>\s*v?(\d+(?:\.\d+)+)\s*?</im,
      },
      downloads: {
        url:   "https://bitbucket.org/abc/def/downloads/",
        regex: /href=.*?ghi-v?(\d+(?:\.\d+)+)\.t/i,
      },
    }
  end

  describe "::match?" do
    it "returns true for a Bitbucket URL" do
      expect(bitbucket.match?(bitbucket_urls[:get])).to be true
      expect(bitbucket.match?(bitbucket_urls[:downloads])).to be true
    end

    it "returns false for a non-Bitbucket URL" do
      expect(bitbucket.match?(non_bitbucket_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a Bitbucket URL" do
      expect(bitbucket.generate_input_values(bitbucket_urls[:get])).to eq(generated[:get])
      expect(bitbucket.generate_input_values(bitbucket_urls[:downloads])).to eq(generated[:downloads])
    end

    it "returns an empty hash for a non-Bitbucket URL" do
      expect(bitbucket.generate_input_values(non_bitbucket_url)).to eq({})
    end
  end
end
