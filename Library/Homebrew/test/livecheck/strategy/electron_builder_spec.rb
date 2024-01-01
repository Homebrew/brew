# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::ElectronBuilder do
  subject(:electron_builder) { described_class }

  let(:http_url) { "https://www.example.com/example/latest-mac.yml" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:regex) { /Example[._-]v?(\d+(?:\.\d+)+)[._-]mac\.zip/i }

  let(:content) do
    <<~EOS
      version: 1.2.3
      files:
        - url: Example-1.2.3-mac.zip
          sha512: MDXR0pxozBJjxxbtUQJOnhiaiiQkryLAwtcVjlnNiz30asm/PtSxlxWKFYN3kV/kl+jriInJrGypuzajTF6XIA==
          size: 92031237
          blockMapSize: 96080
        - url: Example-1.2.3.dmg
          sha512: k6WRDlZEfZGZHoOfUShpHxXZb5p44DRp+FAO2FXNx2kStZvyW9VuaoB7phPMfZpcMKrzfRfncpP8VEM8OB2y9g==
          size: 94972630
      path: Example-1.2.3-mac.zip
      sha512: MDXR0pxozBJjxxbtUQJOnhiaiiQkryLAwtcVjlnNiz30asm/PtSxlxWKFYN3kV/kl+jriInJrGypuzajTF6XIA==
      releaseDate: '2000-01-01T00:00:00.000Z'
    EOS
  end

  let(:content_timestamp) do
    # An electron-builder YAML file may use a timestamp instead of an explicit
    # string value (with quotes) for `releaseDate`, so we need to make sure that
    # `ElectronBuilder#versions_from_content` won't encounter an error in this
    # scenario (e.g. `Tried to load unspecified class: Time`).
    content.sub(/releaseDate:\s*'([^']+)'/, 'releaseDate: \1')
  end

  let(:content_matches) { ["1.2.3"] }

  let(:find_versions_return_hash) do
    {
      matches: {
        "1.2.3" => Version.new("1.2.3"),
      },
      regex:   nil,
      url:     http_url,
    }
  end

  let(:find_versions_cached_return_hash) do
    find_versions_return_hash.merge({ cached: true })
  end

  describe "::match?" do
    it "returns true for a YAML file URL" do
      expect(electron_builder.match?(http_url)).to be true
    end

    it "returns false for non-YAML URL" do
      expect(electron_builder.match?(non_http_url)).to be false
    end
  end

  describe "::find_versions?" do
    it "finds versions in provided_content using a block" do
      expect(electron_builder.find_versions(url: http_url, provided_content: content))
        .to eq(find_versions_cached_return_hash)

      expect(electron_builder.find_versions(url: http_url, regex: regex, provided_content: content) do |yaml, regex|
        yaml["path"][regex, 1]
      end).to eq(find_versions_cached_return_hash.merge({ regex: regex }))

      expect(electron_builder.find_versions(
        url:              http_url,
        regex:            regex,
        provided_content: content_timestamp,
      ) do |yaml, regex|
        yaml["path"][regex, 1]
      end).to eq(find_versions_cached_return_hash.merge({ regex: regex }))

      # NOTE: A regex should be provided using the `#regex` method in a
      # `livecheck` block but we're using a regex literal in the `strategy`
      # block here simply to ensure this method works as expected when a
      # regex isn't provided.
      expect(electron_builder.find_versions(url: http_url, provided_content: content) do |yaml|
        regex = /^v?(\d+(?:\.\d+)+)$/i.freeze
        yaml["version"][regex, 1]
      end).to eq(find_versions_cached_return_hash)
    end

    it "errors if a block is not provided" do
      expect { electron_builder.find_versions(url: http_url, regex: regex, provided_content: content) }
        .to raise_error(ArgumentError, "ElectronBuilder only supports a regex when using a `strategy` block")
    end

    it "returns default match_data when url is blank" do
      expect(electron_builder.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(electron_builder.find_versions(url: http_url, provided_content: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: http_url, cached: true })
    end
  end
end
