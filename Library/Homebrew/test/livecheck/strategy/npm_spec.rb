# frozen_string_literal: true

require "livecheck/strategy/npm"

RSpec.describe Homebrew::Livecheck::Strategy::Npm do
  subject(:npm) { described_class }

  let(:npm_urls) do
    {
      typical:    "https://registry.npmjs.org/abc/-/def-1.2.3.tgz",
      org_scoped: "https://registry.npmjs.org/@example/abc/-/def-1.2.3.tgz",
    }
  end
  let(:non_npm_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      typical:    {
        url:   "https://www.npmjs.com/package/abc?activeTab=versions",
        regex: %r{href=.*?/package/abc/v/(\d+(?:\.\d+)+)"}i,
      },
      org_scoped: {
        url:   "https://www.npmjs.com/package/@example/abc?activeTab=versions",
        regex: %r{href=.*?/package/@example/abc/v/(\d+(?:\.\d+)+)"}i,
      },
    }
  end

  describe "::match?" do
    it "returns true for an npm URL" do
      expect(npm.match?(npm_urls[:typical])).to be true
      expect(npm.match?(npm_urls[:org_scoped])).to be true
    end

    it "returns false for a non-npm URL" do
      expect(npm.match?(non_npm_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an npm URL" do
      expect(npm.generate_input_values(npm_urls[:typical])).to eq(generated[:typical])
      expect(npm.generate_input_values(npm_urls[:org_scoped])).to eq(generated[:org_scoped])
    end

    it "returns an empty hash for a non-npm URL" do
      expect(npm.generate_input_values(non_npm_url)).to eq({})
    end
  end
end
