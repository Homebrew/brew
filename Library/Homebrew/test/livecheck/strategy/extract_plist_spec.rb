# frozen_string_literal: true

require "livecheck/strategy"
require "bundle_version"

RSpec.describe Homebrew::Livecheck::Strategy::ExtractPlist do
  subject(:extract_plist) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:items) do
    {
      "first"  => extract_plist::Item.new(
        bundle_version: Homebrew::BundleVersion.new(nil, "1.2"),
      ),
      "second" => extract_plist::Item.new(
        bundle_version: Homebrew::BundleVersion.new(nil, "1.2.3"),
      ),
    }
  end

  let(:multipart_items) do
    {
      "first"  => extract_plist::Item.new(
        bundle_version: Homebrew::BundleVersion.new(nil, "1.2.3-45"),
      ),
      "second" => extract_plist::Item.new(
        bundle_version: Homebrew::BundleVersion.new(nil, "1.2.3-45-abcdef"),
      ),
    }
  end
  let(:multipart_regex) { /^v?(\d+(?:\.\d+)+)(?:[._-](\d+))?(?:[._-]([0-9a-f]+))?$/i }

  let(:versions) { ["1.2", "1.2.3"] }
  let(:multipart_versions) { ["1.2.3,45", "1.2.3,45,abcdef"] }

  describe "Item" do
    describe "#to_h" do
      it "returns a hash containing non-nil values" do
        expect(items["first"].to_h).to eq({
          bundle_version: { version: "1.2" },
        })
        expect(extract_plist::Item.new.to_h).to eq({})
      end
    end
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(extract_plist.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(extract_plist.match?(non_http_url)).to be false
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if Items hash is empty" do
      expect(extract_plist.versions_from_content({})).to eq([])
    end

    it "returns an array of version strings when given Items" do
      expect(extract_plist.versions_from_content(items)).to eq(versions)
    end

    it "returns an array of version strings when given Items and a block" do
      # Returning a string from block
      expect(
        extract_plist.versions_from_content(items) do |items|
          items["first"].version
        end,
      ).to eq(["1.2"])

      # Returning an array of strings from block
      expect(
        extract_plist.versions_from_content(items) do |items|
          items.map do |_key, item|
            item.bundle_version.nice_version
          end
        end,
      ).to eq(versions)
    end

    it "returns an array of version strings when given `Item`s, a regex and a block" do
      # Returning a string from block
      expect(
        extract_plist.versions_from_content(multipart_items, multipart_regex) do |items, regex|
          match = items["first"].version.match(regex)
          next if match.blank?

          match[1..].compact.join(",")
        end,
      ).to eq(["1.2.3,45"])

      # Returning an array of strings from block
      expect(
        extract_plist.versions_from_content(multipart_items, multipart_regex) do |items, regex|
          items.map do |_key, item|
            match = item.version.match(regex)
            next if match.blank?

            match[1..].compact.join(",")
          end
        end,
      ).to eq(multipart_versions)
    end

    it "allows a nil return from a block" do
      expect(extract_plist.versions_from_content(items) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { extract_plist.versions_from_content(items) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::cask_with_url" do
    it "returns a cask using the url and supported options from the `livecheck` block" do
      cask = Cask::CaskLoader.load(cask_path("livecheck/livecheck-extract-plist-with-url"))
      cask.livecheck.url(
        cask.livecheck.url,
        cookies:    { "key" => "value" },
        header:     "Origin: https://example.com",
        referer:    "https://example.com/referer",
        user_agent: :browser,
      )
      livecheck_url = cask.livecheck.url
      url_options = cask.livecheck.options.url_options

      returned_cask = extract_plist.cask_with_url(cask, livecheck_url, url_options)
      returned_cask_url = returned_cask.url

      expect(returned_cask_url.to_s).to eq(livecheck_url)
      # NOTE: `Cask::URL` converts symbol keys to strings
      expect(returned_cask_url.cookies).to eq(url_options[:cookies].transform_keys(&:to_s))
      # NOTE: `Cask::URL` creates an array from a header string argument
      expect(returned_cask_url.header).to eq([url_options[:header]])
      expect(returned_cask_url.referer).to eq(url_options[:referer])
      expect(returned_cask_url.user_agent).to eq(url_options[:user_agent])
    end

    it "errors if the `livecheck` block uses options not supported by `Cask::URL`" do
      cask = Cask::CaskLoader.load(cask_path("livecheck/livecheck-extract-plist-with-url"))
      livecheck_url = cask.livecheck.url
      cask.livecheck.url(
        livecheck_url,
        post_form:  { key: "value" },
        user_agent: :browser,
      )
      options = cask.livecheck.options

      expect do
        extract_plist.cask_with_url(cask, livecheck_url, options.url_options)
      end.to raise_error(
        ArgumentError,
        "Cask `url` does not support `post_form` option from `livecheck` block",
      )

      options.homebrew_curl = true
      expect do
        extract_plist.cask_with_url(cask, livecheck_url, options.url_options)
      end.to raise_error(
        ArgumentError,
        "Cask `url` does not support `homebrew_curl`, `post_form` options from `livecheck` block",
      )
    end
  end

  describe "::find_versions" do
    let(:cask) { Cask::CaskLoader.load(cask_path("livecheck/livecheck-extract-plist")) }
    let(:content) { '{"com.caffeine":{"bundle_version":{"version":"1.2.3"}}}' }
    let(:match_data) do
      base = {
        matches: { "1.2.3" => Version.new("1.2.3") },
        regex:   nil,
        url:     nil,
      }

      {
        uncached:       base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    it "raises an error if a regex is provided with no block" do
      expect do
        extract_plist.find_versions(cask:, regex: multipart_regex)
      end.to raise_error(ArgumentError, "ExtractPlist only supports a regex when using a `strategy` block")
    end

    it "finds versions using provided content" do
      expect(extract_plist.find_versions(cask:, content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # regex in a `strategy` block.
      expect(extract_plist.find_versions(cask:, content:) do |items|
        items["com.caffeine"]&.version
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when provided content is blank" do
      expect(extract_plist.find_versions(cask:, content: "{}"))
        .to eq(match_data[:cached_default])
    end

    it "checks the cask using the livecheck URL string", :needs_macos do
      cask_with_url = Cask::CaskLoader.load(cask_path("livecheck/livecheck-extract-plist-with-url"))
      livecheck_url = cask_with_url.livecheck.url

      expect(
        extract_plist.find_versions(cask: cask_with_url, url: livecheck_url),
      ).to eq(match_data[:uncached].merge({ url: livecheck_url }))
    end

    it "checks the original cask if the provided URL is the same as the artifact URL", :needs_macos do
      cask_url = cask.url.to_s

      expect(extract_plist.find_versions(cask:, url: cask_url))
        .to eq(match_data[:uncached].merge({ url: cask_url }))
    end

    it "checks the original cask if a URL is not provided", :needs_macos do
      expect(extract_plist.find_versions(cask:)).to eq(match_data[:uncached])
    end
  end
end
