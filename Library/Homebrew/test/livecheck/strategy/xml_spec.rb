# frozen_string_literal: true

require "livecheck/strategy"
require "rexml/document"

RSpec.describe Homebrew::Livecheck::Strategy::Xml do
  subject(:xml) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:regex) { /^v?(\d+(?:\.\d+)+)$/i }

  let(:content_version_text) do
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <versions>
        <version>1.1.2</version>
        <version>1.1.2b</version>
        <version>1.1.2a</version>
        <version>1.1.1</version>
        <version>1.1.0</version>
        <version>1.1.0-rc3</version>
        <version>1.1.0-rc2</version>
        <version>1.1.0-rc1</version>
        <version>1.0.x-last</version>
        <version>1.0.3</version>
        <version>1.0.3-rc3</version>
        <version>1.0.3-rc2</version>
        <version>1.0.3-rc1</version>
        <version>1.0.2</version>
        <version>1.0.2-rc1</version>
        <version>1.0.1</version>
        <version>1.0.1-rc1</version>
        <version>1.0.0</version>
        <version>1.0.0-rc1</version>
      </versions>
    EOS
  end

  let(:content_version_attr) do
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <items>
        <item version="1.1.2" />
        <item version="1.1.2b" />
        <item version="1.1.2a" />
        <item version="1.1.1" />
        <item version="1.1.0" />
        <item version="1.1.0-rc3" />
        <item version="1.1.0-rc2" />
        <item version="1.1.0-rc1" />
        <item version="1.0.x-last" />
        <item version="1.0.3" />
        <item version="1.0.3-rc3" />
        <item version="1.0.3-rc2" />
        <item version="1.0.3-rc1" />
        <item version="1.0.2" />
        <item version="1.0.2-rc1" />
        <item version="1.0.1" />
        <item version="1.0.1-rc1" />
        <item version="1.0.0" />
        <item version="1.0.0-rc1" />
      </items>
    EOS
  end

  let(:content_simple) do
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <version>1.2.3</version>
    EOS
  end

  let(:content_undefined_namespace) do
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <something:version>1.2.3</something:version>
    EOS
  end

  let(:parent_child_text) { { parent: "1.2.3", child: "4.5.6" } }
  let(:content_parent_child) do
    # This XML deliberately includes unnecessary whitespace, to ensure that
    # Xml#element_text properly strips the retrieved text.
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <elements>
        <parent>
          #{parent_child_text[:parent]}
          <child> #{parent_child_text[:child]} </child>
        </parent>
        <blank-parent>
          <blank-child></blank-child>
        </blank-parent>
      </elements>
    EOS
  end

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
      regex:,
      url:     http_url,
    }
  end

  let(:find_versions_cached_return_hash) do
    find_versions_return_hash.merge({ cached: true })
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(xml.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(xml.match?(non_http_url)).to be false
    end
  end

  describe "::parse_xml" do
    # TODO: Should we be comparing against an actual REXML::Document object?
    it "returns an REXML::Document when given XML content" do
      expect(xml.parse_xml(content_version_text)).to be_an_instance_of(REXML::Document)
    end

    it "returns an REXML::Document when given XML content with an undefined namespace" do
      expect(xml.parse_xml(content_undefined_namespace)).to be_an_instance_of(REXML::Document)
    end
  end

  describe "::element_text" do
    let(:parent_child_doc) { xml.parse_xml(content_parent_child) }
    let(:parent) { parent_child_doc.get_elements("/elements/parent").first }
    let(:blank_parent) { parent_child_doc.get_elements("/elements/blank-parent").first }

    it "returns the element text if child_name is not provided" do
      expect(xml.element_text(parent)).to eq(parent_child_text[:parent])
    end

    it "returns the child element text if child_name is provided" do
      expect(xml.element_text(parent, "child")).to eq(parent_child_text[:child])
    end

    it "returns `nil` if the provided child element does not exist" do
      expect(xml.element_text(parent, "nonexistent")).to be_nil
    end

    it "returns `nil` if the retrieved text is blank" do
      expect(xml.element_text(blank_parent)).to be_nil
      expect(xml.element_text(blank_parent, "blank-child")).to be_nil
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array when given a block but content is blank" do
      expect(xml.versions_from_content("", regex) { "1.2.3" }).to eq([])
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(xml.versions_from_content(content_simple) do |xml|
        xml.elements["version"]&.text
      end).to eq(content_simple_matches)
      expect(xml.versions_from_content(content_simple, regex) do |xml|
        version = xml.elements["version"]&.text
        next if version.blank?

        version[regex, 1]
      end).to eq(content_simple_matches)

      # Returning an array of strings from block
      expect(xml.versions_from_content(content_version_text, regex) do |xml, regex|
        xml.get_elements("/versions/version").map { |item| item.text[regex, 1] }
      end).to eq(content_matches)

      expect(xml.versions_from_content(content_version_attr, regex) do |xml, regex|
        xml.get_elements("/items/item").map do |item|
          version = item["version"]
          next if version.blank?

          version[regex, 1]
        end
      end).to eq(content_matches)
    end

    it "allows a nil return from a block" do
      expect(xml.versions_from_content(content_simple, regex) { next }).to eq([])
    end

    it "errors if a block uses two arguments but a regex is not given" do
      expect { xml.versions_from_content(content_simple) { |xml, regex| xml["version"][regex, 1] } }
        .to raise_error("Two arguments found in `strategy` block but no regex provided.")
    end

    it "errors on an invalid return type from a block" do
      expect { xml.versions_from_content(content_simple, regex) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::find_versions?" do
    it "finds versions in provided_content using a block" do
      expect(xml.find_versions(url: http_url, regex:, provided_content: content_version_text) do |xml, regex|
        xml.get_elements("/versions/version").map { |item| item.text[regex, 1] }
      end).to eq(find_versions_cached_return_hash)

      # NOTE: A regex should be provided using the `#regex` method in a
      #       `livecheck` block but we're using a regex literal in the `strategy`
      #       block here simply to ensure this method works as expected when a
      #       regex isn't provided.
      expect(xml.find_versions(url: http_url, provided_content: content_version_text) do |xml|
        regex = /^v?(\d+(?:\.\d+)+)$/i
        xml.get_elements("/versions/version").map { |item| item.text[regex, 1] }
      end).to eq(find_versions_cached_return_hash.merge({ regex: nil }))
    end

    it "errors if a block is not provided" do
      expect { xml.find_versions(url: http_url, provided_content: content_simple) }
        .to raise_error(ArgumentError, "Xml requires a `strategy` block")
    end

    it "returns default match_data when url is blank" do
      expect(xml.find_versions(url: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(xml.find_versions(url: http_url, provided_content: "") { "1.2.3" })
        .to eq({ matches: {}, regex: nil, url: http_url, cached: true })
    end
  end
end
