# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::PageMatch do
  subject(:page_match) { described_class }

  let(:http_url) { "https://brew.sh/blog/" }
  let(:non_http_url) { "ftp://brew.sh/" }

  let(:regex) { %r{href=.*?/homebrew[._-]v?(\d+(?:\.\d+)+)/?["' >]}i }

  let(:content) do
    <<~EOS
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Homebrew — Homebrew</title>
        </head>
        <body>
          <ul class="posts">
            <li><a href="/2020/12/01/homebrew-2.6.0/" title="2.6.0"><h2>2.6.0</h2><h3>01 Dec 2020</h3></a></li>
            <li><a href="/2020/11/18/homebrew-tap-with-bottles-uploaded-to-github-releases/" title="Homebrew tap with bottles uploaded to GitHub Releases"><h2>Homebrew tap with bottles uploaded to GitHub Releases</h2><h3>18 Nov 2020</h3></a></li>
            <li><a href="/2020/09/08/homebrew-2.5.0/" title="2.5.0"><h2>2.5.0</h2><h3>08 Sep 2020</h3></a></li>
            <li><a href="/2020/06/11/homebrew-2.4.0/" title="2.4.0"><h2>2.4.0</h2><h3>11 Jun 2020</h3></a></li>
            <li><a href="/2020/05/29/homebrew-2.3.0/" title="2.3.0"><h2>2.3.0</h2><h3>29 May 2020</h3></a></li>
            <li><a href="/2019/11/27/homebrew-2.2.0/" title="2.2.0"><h2>2.2.0</h2><h3>27 Nov 2019</h3></a></li>
            <li><a href="/2019/06/14/homebrew-maintainer-meeting/" title="Homebrew Maintainer Meeting"><h2>Homebrew Maintainer Meeting</h2><h3>14 Jun 2019</h3></a></li>
            <li><a href="/2019/04/04/homebrew-2.1.0/" title="2.1.0"><h2>2.1.0</h2><h3>04 Apr 2019</h3></a></li>
            <li><a href="/2019/02/02/homebrew-2.0.0/" title="2.0.0"><h2>2.0.0</h2><h3>02 Feb 2019</h3></a></li>
            <li><a href="/2019/01/09/homebrew-1.9.0/" title="1.9.0"><h2>1.9.0</h2><h3>09 Jan 2019</h3></a></li>
          </ul>
        </body>
      </html>
    EOS
  end

  let(:content_matches) { ["2.6.0", "2.5.0", "2.4.0", "2.3.0", "2.2.0", "2.1.0", "2.0.0", "1.9.0"] }

  let(:find_versions_return_hash) do
    {
      matches: {
        "2.6.0" => Version.new("2.6.0"),
        "2.5.0" => Version.new("2.5.0"),
        "2.4.0" => Version.new("2.4.0"),
        "2.3.0" => Version.new("2.3.0"),
        "2.2.0" => Version.new("2.2.0"),
        "2.1.0" => Version.new("2.1.0"),
        "2.0.0" => Version.new("2.0.0"),
        "1.9.0" => Version.new("1.9.0"),
      },
      regex:   regex,
      url:     http_url,
    }
  end

  let(:find_versions_cached_return_hash) do
    return_hash = find_versions_return_hash
    return_hash[:cached] = true
    return_hash
  end

  describe "::match?" do
    it "returns true for an HTTP URL" do
      expect(page_match.match?(http_url)).to be true
    end

    it "returns false for a non-HTTP URL" do
      expect(page_match.match?(non_http_url)).to be false
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if content is blank" do
      expect(page_match.versions_from_content("", regex)).to eq([])
    end

    it "returns an array of version strings when given content" do
      expect(page_match.versions_from_content(content, regex)).to eq(content_matches)

      # Regexes should use a capture group around the version but a regex
      # without one should still be handled
      expect(page_match.versions_from_content(content, /\d+(?:\.\d+)+/i)).to eq(content_matches)
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(page_match.versions_from_content(content, regex) { "1.2.3" }).to eq(["1.2.3"])

      # Returning an array of strings from block
      expect(page_match.versions_from_content(content, regex) { |page, regex| page.scan(regex).map(&:first) })
        .to eq(content_matches)
    end

    it "allows a nil return from a block" do
      expect(page_match.versions_from_content(content, regex) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { page_match.versions_from_content(content, regex) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::find_versions?" do
    it "finds versions in provided_content" do
      expect(page_match.find_versions(url: http_url, regex: regex, provided_content: content))
        .to eq(find_versions_cached_return_hash)

      # NOTE: Ideally, a regex should always be provided to `#find_versions`
      # for `PageMatch` but there are currently some `livecheck` blocks in
      # casks where `#regex` isn't used and the regex only exists within a
      # `strategy` block. This isn't ideal but, for the moment, we allow a
      # `strategy` block to act as a substitution for a regex and we need to
      # test this scenario to ensure it works.
      #
      # Under normal circumstances, a regex should be established in a
      # `livecheck` block using `#regex` and passed into the `strategy` block
      # using `do |page, regex|`. Hopefully over time we can address related
      # issues and get to a point where regexes are always established using
      # `#regex`.
      expect(page_match.find_versions(url: http_url, provided_content: content) do |page|
        page.scan(%r{href=.*?/homebrew[._-]v?(\d+(?:\.\d+)+)/?["' >]}i).map(&:first)
      end)
        .to eq(find_versions_cached_return_hash.merge({ regex: nil }))
    end
  end
end
