# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Json do
  subject(:json) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:regex) { /^v?(\d+(?:\.\d+)+)$/i }

  let(:content) do
    <<~EOS
      {
        "versions": [
          { "version": "1.1.2" },
          { "version": "1.1.2b" },
          { "version": "1.1.2a" },
          { "version": "1.1.1" },
          { "version": "1.1.0" },
          { "version": "1.1.0-rc3" },
          { "version": "1.1.0-rc2" },
          { "version": "1.1.0-rc1" },
          { "version": "1.0.x-last" },
          { "version": "1.0.3" },
          { "version": "1.0.3-rc3" },
          { "version": "1.0.3-rc2" },
          { "version": "1.0.3-rc1" },
          { "version": "1.0.2" },
          { "version": "1.0.2-rc1" },
          { "version": "1.0.1" },
          { "version": "1.0.1-rc1" },
          { "version": "1.0.0" },
          { "version": "1.0.0-rc1" },
          { "other": "version is omitted from this object for testing" }
        ]
      }
    EOS
  end
  let(:content_simple) { '{"version":"1.2.3"}' }

  let(:content_matches) { ["1.1.2", "1.1.1", "1.1.0", "1.0.3", "1.0.2", "1.0.1", "1.0.0"] }
  let(:content_simple_matches) { ["1.2.3"] }

  let(:find_versions_return_hash) do
    {
      matches: {
        "1.1.2" => Version.new("1.1.2"),
        "1.1.1" => Version.new("1.1.1"),
        "1.1.0" => Version.new("1.1.0"),
        "1.0.3" => Version.new("1.0.3"),
        "1.0.2" => Version.new("1.0.2"),
        "1.0.1" => Version.new("1.0.1"),
        "1.0.0" => Version.new("1.0.0"),
      },
      regex:   regex,
      url:     http_url,
    }
  end

  let(:find_versions_cached_return_hash) do
    find_versions_return_hash.merge({ cached: true })
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(json.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(json.match?(non_http_url)).to be false
    end
  end

  describe "::parse_json" do
    it "returns an object when given valid content" do
      expect(json.parse_json(content_simple)).to be_an_instance_of(Hash)
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array when given a block but content is blank" do
      expect(json.versions_from_content("", regex) { "1.2.3" }).to eq([])
    end

    it "errors if provided content is not valid JSON" do
      expect { json.versions_from_content("not valid JSON") { [] } }
        .to raise_error(RuntimeError, "Content could not be parsed as JSON.")
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(json.versions_from_content(content_simple) { |json| json["version"] }).to eq(content_simple_matches)
      expect(json.versions_from_content(content_simple, regex) do |json|
        json["version"][regex, 1]
      end).to eq(content_simple_matches)

      # Returning an array of strings from block
      expect(json.versions_from_content(content, regex) do |json, regex|
        json["versions"].select { |item| item["version"]&.match?(regex) }
                        .map { |item| item["version"][regex, 1] }
      end).to eq(content_matches)
    end

    it "allows a nil return from a block" do
      expect(json.versions_from_content(content_simple, regex) { next }).to eq([])
    end

    it "errors if a block uses two arguments but a regex is not given" do
      expect { json.versions_from_content(content_simple) { |json, regex| json["version"][regex, 1] } }
        .to raise_error("Two arguments found in `strategy` block but no regex provided.")
    end

    it "errors on an invalid return type from a block" do
      expect { json.versions_from_content(content_simple, regex) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::find_versions?" do
    it "finds versions in provided_content using a block" do
      expect(json.find_versions(url: http_url, regex: regex, provided_content: content) do |json, regex|
        json["versions"].select { |item| item["version"]&.match?(regex) }
                        .map { |item| item["version"][regex, 1] }
      end).to eq(find_versions_cached_return_hash)

      # NOTE: A regex should be provided using the `#regex` method in a
      # `livecheck` block but we're using a regex literal in the `strategy`
      # block here simply to ensure this method works as expected when a
      # regex isn't provided.
      expect(json.find_versions(url: http_url, provided_content: content) do |json|
        regex = /^v?(\d+(?:\.\d+)+)$/i.freeze
        json["versions"].select { |item| item["version"]&.match?(regex) }
                        .map { |item| item["version"][regex, 1] }
      end).to eq(find_versions_cached_return_hash.merge({ regex: nil }))
    end

    it "errors if a block is not provided" do
      expect { json.find_versions(url: http_url, provided_content: content) }
        .to raise_error(ArgumentError, "Json requires a `strategy` block")
    end

    it "returns default match_data when url is blank" do
      expect(json.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(json.find_versions(url: http_url, provided_content: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: http_url, cached: true })
    end
  end
end
