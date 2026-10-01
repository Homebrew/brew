# typed: true
# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::HeaderMatch do
  subject(:header_match) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }
  let(:regexes) do
    {
      archive: /filename=brew[._-]v?(\d+(?:\.\d+)+)\.t/i,
      latest:  %r{.*?/tag/v?(\d+(?:\.\d+)+)$}i,
      loose:   /v?(\d+(?:\.\d+)+)/i,
    }
  end
  let(:headers) do
    headers = {
      content_disposition: {
        "date"                => "Fri, 01 Jan 2021 01:23:45 GMT",
        "content-type"        => "application/x-gzip",
        "content-length"      => "120",
        "content-disposition" => "attachment; filename=brew-1.2.3.tar.gz",
      },
      location:            {
        "date"           => "Fri, 01 Jan 2021 01:23:45 GMT",
        "content-type"   => "text/html; charset=utf-8",
        "location"       => "https://github.com/Homebrew/brew/releases/tag/1.2.4",
        "content-length" => "117",
      },
    }
    headers[:content_disposition_and_location] = headers[:content_disposition].merge(headers[:location])
    headers[:no_version] = headers[:content_disposition_and_location].merge({
      "content-disposition" => "attachment; filename=brew.tar.gz",
      "location"            => http_url,
    })

    # Location headers shouldn't appear more than once in an HTTP response but
    # this is intended to exercise related logic in `versions_from_content`.
    headers[:location_array] = headers[:location].merge({
      "location" => [
        "https://example.com/",
        "https://github.com/Homebrew/brew/releases/tag/1.2.4",
      ],
    })

    headers
  end
  let(:matches) do
    matches = {
      content_disposition: ["1.2.3"],
      location:            ["1.2.4"],
    }
    matches[:content_disposition_and_location] = matches[:content_disposition] + matches[:location]

    matches
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(header_match.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(header_match.match?(non_http_url)).to be false
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if headers hash is empty" do
      expect(header_match.versions_from_content([{}])).to eq([])
    end

    it "returns an empty array if checked headers do not contain versions" do
      expect(header_match.versions_from_content([headers[:no_version]])).to eq([])
    end

    it "returns an array of version strings when given headers" do
      expect(header_match.versions_from_content([headers[:content_disposition]])).to eq(matches[:content_disposition])
      expect(header_match.versions_from_content([headers[:location]])).to eq(matches[:location])
      expect(header_match.versions_from_content([headers[:content_disposition_and_location]]))
        .to eq(matches[:content_disposition_and_location])
      expect(header_match.versions_from_content([headers[:location_array]]))
        .to eq(matches[:location])

      expect(header_match.versions_from_content([headers[:content_disposition]], regexes[:archive]))
        .to eq(matches[:content_disposition])
      expect(header_match.versions_from_content([headers[:location]], regexes[:latest])).to eq(matches[:location])
      expect(header_match.versions_from_content([headers[:content_disposition_and_location]], regexes[:latest]))
        .to eq(matches[:location])
      expect(header_match.versions_from_content([headers[:location_array]], regexes[:latest]))
        .to eq(matches[:location])
    end

    it "returns an array of version strings when given headers and a block" do
      # Returning a string from block, no regex.
      expect(
        header_match.versions_from_content([headers[:location]]) do |headers|
          v = Version.parse(headers["location"], detected_from_url: true)
          v.null? ? nil : v.to_s
        end,
      ).to eq(matches[:location])
      expect(
        header_match.versions_from_content([headers[:location]]) do |all_headers|
          location = all_headers[0]&.[]("location")
          next unless location

          v = Version.parse(location, detected_from_url: true)
          v.null? ? nil : v.to_s
        end,
      ).to eq(matches[:location])

      # Returning a string from block, explicit regex.
      expect(
        header_match.versions_from_content([headers[:location]], regexes[:latest]) do |headers, regex|
          headers["location"] ? headers["location"][regex, 1] : nil
        end,
      ).to eq(matches[:location])
      expect(
        header_match.versions_from_content([headers[:location]], regexes[:latest]) do |all_headers, regex|
          location = all_headers[0]&.[]("location")
          location ? location[regex, 1] : nil
        end,
      ).to eq(matches[:location])

      # Returning an array of strings from block.
      #
      # NOTE: Strategies runs `#compact` on an array from a block, so nil values
      #       are filtered out without needing to use `#compact` in the block.
      expect(
        header_match.versions_from_content(
          [headers[:content_disposition_and_location]],
          regexes[:loose],
        ) do |headers, regex|
          headers.transform_values { |header| header[regex, 1] }.values
        end,
      ).to eq(matches[:content_disposition_and_location])
      expect(
        header_match.versions_from_content(
          [headers[:content_disposition_and_location]],
          regexes[:loose],
        ) do |all_headers, regex|
          all_headers.map do |headers|
            headers.transform_values { |header| header[regex, 1] }.values
          end.flatten
        end,
      ).to eq(matches[:content_disposition_and_location])
    end

    it "allows a nil return from a block" do
      expect(header_match.versions_from_content([headers[:location]]) do |headers|
        _ = headers # To appease `brew style` without modifying arg name
        next
      end).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect do
        header_match.versions_from_content([headers[:location]]) do |headers|
          _ = headers # To appease `brew style` without modifying arg name
          123
        end
      end.to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end

    it "errors if the first block argument uses an unhandled name" do
      expect { header_match.versions_from_content([headers[:location]]) { |something| something } }
        .to raise_error(
          ArgumentError,
          "First argument of HeaderMatch `strategy` block must be `headers` or `all_headers`",
        )
    end
  end

  describe "::find_versions" do
    let(:content) do
      require "json"
      JSON.generate([headers[:location]])
    end
    let(:match_data) do
      base = {
        matches: matches[:location].to_h { |v| [v, Version.new(v)] },
        regex:   nil,
        url:     http_url,
      }

      {
        fetched:        base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    it "finds versions in fetched content" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_headers).and_return([headers[:location]])

      expect(header_match.find_versions(url: http_url)).to eq(match_data[:fetched])
    end

    it "finds versions in provided content" do
      expect(header_match.find_versions(url: http_url, content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # regex in a `strategy` block.
      expect(
        header_match.find_versions(
          url:     http_url,
          regex:   regexes[:latest],
          content:,
        ) do |headers, regex|
          match = headers["location"]&.match(regex)
          next if match.blank?

          match[1]
        end,
      ).to eq(match_data[:cached].merge({ regex: regexes[:latest] }))
    end

    it "returns default match_data when url is blank" do
      expect(header_match.find_versions(url: "", content:))
        .to eq(match_data[:cached_default].merge({ url: "" }))
    end

    it "returns default match_data when content is blank" do
      expect(header_match.find_versions(url: http_url, content: "[]"))
        .to eq(match_data[:cached_default])
      expect(header_match.find_versions(url: http_url, content: "[{}]"))
        .to eq(match_data[:cached_default])
    end
  end
end
