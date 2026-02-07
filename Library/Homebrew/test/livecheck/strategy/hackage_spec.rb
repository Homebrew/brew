# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Hackage do
  subject(:hackage) { described_class }

  let(:hackage_urls) do
    {
      package:   "https://hackage.haskell.org/package/abc-1.2.3/abc-1.2.3.tar.gz",
      downloads: "https://downloads.haskell.org/~abc/1.2.3/abc-1.2.3-src.tar.xz",
    }
  end
  let(:non_hackage_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:   "https://hackage.haskell.org/package/abc/src/",
      regex: %r{<h3>abc-(.*?)/?</h3>}i,
    }
  end

  let(:content) do
    <<~EOS
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
      <html xmlns="http://www.w3.org/1999/xhtml">
      <head>
        <title>Directory listing for abc-1.2.3 source tarball | Hackage</title>
      </head>
      <body>
        <div id="content">
          <h2>Directory listing for abc-1.2.3 source tarball</h2>
          <h3>abc-1.2.3/</h3>
          <ul class="directory-list">
            <li>
              <a href="CHANGELOG">CHANGELOG</a>
            </li>
            <li>
              <a href="abc">abc/</a>
              <ul class="directory-list">
                <li>
                  <a href="abc/abc.hs">abc.hs</a>
                </li>
              </ul>
            </li>
          </ul>
        </div>
      </body>
      </html>
    EOS
  end

  let(:matches) { ["1.2.3"] }

  describe "::match?" do
    it "returns true for a Hackage URL" do
      expect(hackage.match?(hackage_urls[:package])).to be true
      expect(hackage.match?(hackage_urls[:downloads])).to be true
    end

    it "returns false for a non-Hackage URL" do
      expect(hackage.match?(non_hackage_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a Hackage URL" do
      expect(hackage.generate_input_values(hackage_urls[:package])).to eq(generated)
      expect(hackage.generate_input_values(hackage_urls[:downloads])).to eq(generated)
    end

    it "returns an empty hash for a non-Hackage URL" do
      expect(hackage.generate_input_values(non_hackage_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:regex],
        url:     generated[:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(hackage.find_versions(url: hackage_urls[:package], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(hackage.find_versions(url: hackage_urls[:package], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(hackage.find_versions(url: hackage_urls[:package], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
