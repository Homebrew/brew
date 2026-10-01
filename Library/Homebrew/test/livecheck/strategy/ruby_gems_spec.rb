# typed: true
# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::RubyGems do
  subject(:ruby_gems) { described_class }

  let(:ruby_gems_url) { "https://rubygems.org/downloads/example-package-1.2.3.gem" }
  let(:platform_ruby_gems_url) { "https://rubygems.org/downloads/example-package-1.2.3-arm64-darwin.gem" }
  let(:non_ruby_gems_url) { "https://brew.sh/test" }
  let(:generated) do
    {
      url: "https://rubygems.org/api/v1/versions/example-package/latest.json",
    }
  end
  let(:content) do
    <<~JSON
      {
        "version": "1.2.3"
      }
    JSON
  end

  describe "::match?" do
    it "returns true for a RubyGems URL" do
      expect(ruby_gems.match?(ruby_gems_url)).to be true
      expect(ruby_gems.match?(platform_ruby_gems_url)).to be true
    end

    it "returns false for a non-RubyGems URL" do
      expect(ruby_gems.match?(non_ruby_gems_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url for a RubyGems URL" do
      expect(ruby_gems.generate_input_values(ruby_gems_url)).to eq(generated)
      expect(ruby_gems.generate_input_values(platform_ruby_gems_url)).to eq(generated)
    end

    it "returns an empty hash for a non-RubyGems URL" do
      expect(ruby_gems.generate_input_values(non_ruby_gems_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      {
        matches: {
          "1.2.3" => Version.new("1.2.3"),
        },
        regex:   nil,
        url:     generated[:url],
      }
    end

    it "finds versions in fetched content" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: })

      expect(ruby_gems.find_versions(url: ruby_gems_url)).to eq(match_data.merge({ content: }))
    end

    it "finds versions in provided content" do
      expect(ruby_gems.find_versions(url: ruby_gems_url, content:)).to eq(match_data.merge({ cached: true }))
    end

    it "finds versions in provided content using a block" do
      expect(ruby_gems.find_versions(url: ruby_gems_url, content:) do |json|
        json["version"]
      end).to eq(match_data.merge({ cached: true }))
    end

    it "returns default match_data when block doesn't return version information" do
      expect(ruby_gems.find_versions(url: ruby_gems_url, content:) do |json|
        json["nonexistent_value"]
      end).to eq(match_data.merge({ matches: {}, cached: true }))
    end

    it "returns default match_data when url is blank" do
      expect(ruby_gems.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(ruby_gems.find_versions(url: ruby_gems_url, content: ""))
        .to eq(match_data.merge({ matches: {}, cached: true }))
    end
  end
end
