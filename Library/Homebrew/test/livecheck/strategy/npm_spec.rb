# frozen_string_literal: true

require "livecheck/strategy"

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
        url: "https://registry.npmjs.org/abc/latest",
      },
      org_scoped: {
        url: "https://registry.npmjs.org/%40example%2Fabc/latest",
      },
    }
  end

  # This is a limited subset of a `latest` response object, for the sake of
  # testing.
  let(:content) do
    <<~EOS
      {
        "name": "example",
        "version": "1.2.3"
      }
    EOS
  end

  let(:matches) { ["1.2.3"] }

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

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   nil,
        url:     generated[:typical][:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(npm.find_versions(url: npm_urls[:typical], provided_content: content))
        .to eq(match_data[:cached])
    end

    it "finds versions in provided content using a block" do
      # This `strategy` block is unnecessary but it's only intended to test
      # using a provided `strategy` block.
      expect(npm.find_versions(url: npm_urls[:typical], provided_content: content) do |json|
        json["version"]
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when block doesn't return version information" do
      expect(npm.find_versions(url: npm_urls[:typical], provided_content: content) do |json|
        json["nonexistentValue"]
      end).to eq(match_data[:cached_default])
    end

    it "returns default match_data when url is blank" do
      expect(npm.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(npm.find_versions(url: npm_urls[:typical], provided_content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
