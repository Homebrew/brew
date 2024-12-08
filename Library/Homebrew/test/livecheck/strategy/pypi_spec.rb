# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Pypi do
  subject(:pypi) { described_class }

  let(:pypi_url) { "https://files.pythonhosted.org/packages/ab/cd/efg/example-package-1.2.3.tar.gz" }
  let(:non_pypi_url) { "https://brew.sh/test" }

  let(:regex) { /^v?(\d+(?:\.\d+)+)/i }

  let(:generated) do
    {
      url: "https://pypi.org/pypi/example-package/json",
    }
  end

  # This is a limited subset of a PyPI JSON API response object, for the sake
  # of testing. Typical versions use a `1.2.3` format but this adds a suffix,
  # so we can test regex matching.
  let(:content) do
    <<~JSON
      {
        "info": {
          "version": "1.2.3-456"
        }
      }
    JSON
  end

  let(:matches) { ["1.2.3-456"] }

  let(:find_versions_return_hash) do
    {
      matches: {
        "1.2.3-456" => Version.new("1.2.3-456"),
      },
      regex:,
      url:     generated[:url],
    }
  end

  let(:find_versions_cached_return_hash) do
    find_versions_return_hash.merge({ cached: true })
  end

  describe "::match?" do
    it "returns true for a PyPI URL" do
      expect(pypi.match?(pypi_url)).to be true
    end

    it "returns false for a non-PyPI URL" do
      expect(pypi.match?(non_pypi_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an PyPI URL" do
      expect(pypi.generate_input_values(pypi_url)).to eq(generated)
    end

    it "returns an empty hash for a non-PyPI URL" do
      expect(pypi.generate_input_values(non_pypi_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   nil,
        url:     generated[:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
        cached_regex:   cached.merge({
          matches: { "1.2.3" => Version.new("1.2.3") },
          regex:,
        }),
      }
    end

    it "finds versions in provided content" do
      expect(pypi.find_versions(url: pypi_url, regex:, provided_content: content))
        .to eq(match_data[:cached_regex])

      expect(pypi.find_versions(url: pypi_url, provided_content: content))
        .to eq(match_data[:cached])
    end

    it "finds versions in provided content using a block" do
      # NOTE: We only use a regex here to make sure it can be passed into the
      # block, if necessary.
      expect(pypi.find_versions(url: pypi_url, regex:, provided_content: content) do |json, regex|
        match = json.dig("info", "version")&.match(regex)
        next if match.blank?

        match[1]
      end).to eq(match_data[:cached_regex])

      expect(pypi.find_versions(url: pypi_url, provided_content: content) do |json|
        json.dig("info", "version").presence
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when block doesn't return version information" do
      no_match_regex = /will_not_match/i

      expect(pypi.find_versions(url: pypi_url, provided_content: '{"info":{"version":""}}'))
        .to eq(match_data[:cached_default])
      expect(pypi.find_versions(url: pypi_url, provided_content: '{"other":true}'))
        .to eq(match_data[:cached_default])
      expect(pypi.find_versions(url: pypi_url, regex: no_match_regex, provided_content: content))
        .to eq(match_data[:cached_default].merge({ regex: no_match_regex }))
    end

    it "returns default match_data when url is blank" do
      expect(pypi.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(pypi.find_versions(url: pypi_url, provided_content: "{}") { "1.2.3" })
        .to eq(match_data[:cached_default])
      expect(pypi.find_versions(url: pypi_url, provided_content: "") { "1.2.3" })
        .to eq(match_data[:cached_default])
    end
  end
end
