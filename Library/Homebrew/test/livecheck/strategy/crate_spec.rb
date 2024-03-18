# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Crate do
  subject(:crate) { described_class }

  let(:crate_url) { "https://static.crates.io/crates/example/example-0.1.0.crate" }
  let(:non_crate_url) { "https://brew.sh/test" }

  let(:regex) { /^v?(\d+(?:\.\d+)+)$/i }

  let(:generated) do
    { url: "https://crates.io/api/v1/crates/example/versions" }
  end

  # This is a limited subset of a `versions` response object, for the sake of
  # testing.
  let(:content) do
    <<~EOS
      {
        "versions": [
          {
            "crate": "example",
            "created_at": "2023-01-03T00:00:00.000000+00:00",
            "num": "1.0.2",
            "updated_at": "2023-01-03T00:00:00.000000+00:00",
            "yanked": true
          },
          {
            "crate": "example",
            "created_at": "2023-01-02T00:00:00.000000+00:00",
            "num": "1.0.1",
            "updated_at": "2023-01-02T00:00:00.000000+00:00",
            "yanked": false
          },
          {
            "crate": "example",
            "created_at": "2023-01-01T00:00:00.000000+00:00",
            "num": "1.0.0",
            "updated_at": "2023-01-01T00:00:00.000000+00:00",
            "yanked": false
          }
        ]
      }
    EOS
  end

  let(:matches) { ["1.0.0", "1.0.1"] }

  let(:find_versions_return_hash) do
    {
      matches: {
        "1.0.1" => Version.new("1.0.1"),
        "1.0.0" => Version.new("1.0.0"),
      },
      regex:,
      url:     generated[:url],
    }
  end

  let(:find_versions_cached_return_hash) do
    find_versions_return_hash.merge({ cached: true })
  end

  describe "::match?" do
    it "returns true for a crate URL" do
      expect(crate.match?(crate_url)).to be true
    end

    it "returns false for a non-crate URL" do
      expect(crate.match?(non_crate_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url for a crate URL" do
      expect(crate.generate_input_values(crate_url)).to eq(generated)
    end

    it "returns an empty hash for a non-crate URL" do
      expect(crate.generate_input_values(non_crate_url)).to eq({})
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
      }
    end

    it "finds versions in provided content" do
      expect(crate.find_versions(url: crate_url, regex:, provided_content: content))
        .to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, provided_content: content))
        .to eq(match_data[:cached])
    end

    it "finds versions in provided content using a block" do
      expect(crate.find_versions(url: crate_url, regex:, provided_content: content) do |json, regex|
        json["versions"]&.map do |version|
          next if version["yanked"] == true
          next if (match = version["num"]&.match(regex)).blank?

          match[1]
        end
      end).to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, provided_content: content) do |json|
        json["versions"]&.map do |version|
          next if version["yanked"] == true
          next if (match = version["num"]&.match(regex)).blank?

          match[1]
        end
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when block doesn't return version information" do
      no_match_regex = /will_not_match/i

      expect(crate.find_versions(url: crate_url, provided_content: '{"other":true}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, provided_content: '{"versions":[{}]}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, regex: no_match_regex, provided_content: content))
        .to eq(match_data[:cached_default].merge({ regex: no_match_regex }))
    end

    it "returns default match_data when url is blank" do
      expect(crate.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(crate.find_versions(url: crate_url, provided_content: "{}") { "1.2.3" })
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, provided_content: "") { "1.2.3" })
        .to eq(match_data[:cached_default])
    end
  end
end
