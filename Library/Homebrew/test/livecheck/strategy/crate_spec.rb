# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Crate do
  subject(:crate) { described_class }

  let(:crate_url) { "https://static.crates.io/crates/example/example-0.1.0.crate" }
  let(:non_crate_url) { "https://brew.sh/test" }

  # This only differs from the `DEFAULT_REGEX` so we can distinguish between a
  # provided regex and the default strategy regex in testing.
  let(:regex) { /v?(\d+(?:\.\d+)+)/i }

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
      regex:   crate::DEFAULT_REGEX,
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
      base = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   nil,
        url:     generated[:url],
      }

      {
        fetched:        base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    it "finds versions in fetched content" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: })

      expect(crate.find_versions(url: crate_url, regex:))
        .to eq(match_data[:fetched].merge({ regex: }))
      expect(crate.find_versions(url: crate_url)).to eq(match_data[:fetched])
    end

    it "finds versions in provided content" do
      expect(crate.find_versions(url: crate_url, regex:, content:))
        .to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, content:))
        .to eq(match_data[:cached])
    end

    it "finds versions in provided content using a block" do
      expect(crate.find_versions(url: crate_url, regex:, content:) do |json, regex|
        json["versions"]&.map do |version|
          next if version["yanked"] == true
          next if (match = version["num"]&.match(regex)).blank?

          match[1]
        end
      end).to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, content:) do |json|
        json["versions"]&.map do |version|
          next if version["yanked"] == true
          next if (match = version["num"]&.match(regex)).blank?

          match[1]
        end
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when block doesn't return version information" do
      no_match_regex = /will_not_match/i

      expect(crate.find_versions(url: crate_url, content: '{"other":true}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, content: '{"versions":[{}]}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, regex: no_match_regex, content:))
        .to eq(match_data[:cached_default].merge({ regex: no_match_regex }))
    end

    it "returns default match_data when url is blank" do
      expect(crate.find_versions(url: ""))
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(crate.find_versions(url: crate_url, content: "{}"))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
