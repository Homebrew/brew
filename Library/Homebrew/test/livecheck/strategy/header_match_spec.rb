# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::HeaderMatch do
  subject(:header_match) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:versions) do
    versions = {
      content_disposition: ["1.2.3"],
      location:            ["1.2.4"],
    }
    versions[:content_disposition_and_location] = versions[:content_disposition] + versions[:location]

    versions
  end

  let(:headers) do
    headers = {
      content_disposition: {
        "date"                => "Fri, 01 Jan 2021 01:23:45 GMT",
        "content-type"        => "application/x-gzip",
        "content-length"      => "120",
        "content-disposition" => "attachment; filename=brew-#{versions[:content_disposition].first}.tar.gz",
      },
      location:            {
        "date"           => "Fri, 01 Jan 2021 01:23:45 GMT",
        "content-type"   => "text/html; charset=utf-8",
        "location"       => "https://github.com/Homebrew/brew/releases/tag/#{versions[:location].first}",
        "content-length" => "117",
      },
    }
    headers[:content_disposition_and_location] = headers[:content_disposition].merge(headers[:location])

    headers
  end

  let(:regexes) do
    {
      archive: /filename=brew[._-]v?(\d+(?:\.\d+)+)\.t/i,
      latest:  %r{.*?/tag/v?(\d+(?:\.\d+)+)$}i,
      loose:   /v?(\d+(?:\.\d+)+)/i,
    }
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(header_match.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(header_match.match?(non_http_url)).to be false
    end
  end

  describe "::versions_from_headers" do
    it "returns an empty array if headers hash is empty" do
      expect(header_match.versions_from_headers({})).to eq([])
    end

    it "returns an array of version strings when given headers" do
      expect(header_match.versions_from_headers(headers[:content_disposition])).to eq(versions[:content_disposition])
      expect(header_match.versions_from_headers(headers[:location])).to eq(versions[:location])
      expect(header_match.versions_from_headers(headers[:content_disposition_and_location]))
        .to eq(versions[:content_disposition_and_location])

      expect(header_match.versions_from_headers(headers[:content_disposition], regexes[:archive]))
        .to eq(versions[:content_disposition])
      expect(header_match.versions_from_headers(headers[:location], regexes[:latest])).to eq(versions[:location])
      expect(header_match.versions_from_headers(headers[:content_disposition_and_location], regexes[:latest]))
        .to eq(versions[:location])
    end

    it "returns an array of version strings when given headers and a block" do
      # Returning a string from block, no regex
      expect(
        header_match.versions_from_headers(headers[:location]) do |headers|
          v = Version.parse(headers["location"], detected_from_url: true)
          v.null? ? nil : v.to_s
        end,
      ).to eq(versions[:location])

      # Returning a string from block, explicit regex
      expect(
        header_match.versions_from_headers(headers[:location], regexes[:latest]) do |headers, regex|
          headers["location"] ? headers["location"][regex, 1] : nil
        end,
      ).to eq(versions[:location])

      # Returning an array of strings from block
      # NOTE: Strategies runs `#compact` on an array from a block, so nil
      # values are filtered out without needing to use `#compact` in the block.
      expect(
        header_match.versions_from_headers(
          headers[:content_disposition_and_location],
          regexes[:loose],
        ) do |headers, regex|
          headers.transform_values { |header| header[regex, 1] }.values
        end,
      ).to eq(versions[:content_disposition_and_location])
    end

    it "allows a nil return from a block" do
      expect(header_match.versions_from_headers(headers[:location]) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { header_match.versions_from_headers(headers) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
