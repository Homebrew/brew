# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Launchpad do
  subject(:launchpad) { described_class }

  let(:launchpad_urls) do
    {
      version_dir:    "https://launchpad.net/abc/1.2/1.2.3/+download/abc-1.2.3.tar.gz",
      trunk:          "https://launchpad.net/abc/trunk/1.2.3/+download/abc-1.2.3.tar.gz",
      code_subdomain: "https://code.launchpad.net/abc/1.2/1.2.3/+download/abc-1.2.3.tar.gz",
    }
  end
  let(:non_launchpad_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url: "https://launchpad.net/abc/",
    }
  end

  # The whitespace in a real response is a bit looser and this has been
  # reformatted for the sake of brevity.
  let(:content) do
    <<~EOS
      <!DOCTYPE html>
      <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
        <head>
          <meta charset="UTF-8"/>
          <title>abc in Launchpad</title>
        </head>
        <body>
          <div id="downloads" class="top-portlet downloads">
            <h2>Downloads</h2>
            <div class="version">Latest version is 1.2.3</div>
            <ul>
              <li>
                <a href="https://launchpad.net/abc/trunk/1.2.3/+download/abc-1.2.3.tar.gz" title="abc 1.2.3">abc-1.2.3.tar.gz</a>
              </li>
            </ul>

            <div class="released">
              released
              <time title="2022-01-23 01:23:45 UTC" datetime="2022-01-23T01:23:45+00:00">on 2022-01-23</time>
            </div>

            <p class="alternate">
              <a class="sprite info" href="https://launchpad.net/abc/+download">All downloads</a>
            </p>
          </div>
        </body>
      </html>
    EOS
  end

  let(:matches) { ["1.2.3"] }

  describe "::match?" do
    it "returns true for a Launchpad URL" do
      expect(launchpad.match?(launchpad_urls[:version_dir])).to be true
      expect(launchpad.match?(launchpad_urls[:trunk])).to be true
      expect(launchpad.match?(launchpad_urls[:code_subdomain])).to be true
    end

    it "returns false for a non-Launchpad URL" do
      expect(launchpad.match?(non_launchpad_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an Launchpad URL" do
      expect(launchpad.generate_input_values(launchpad_urls[:version_dir])).to eq(generated)
      expect(launchpad.generate_input_values(launchpad_urls[:trunk])).to eq(generated)
      expect(launchpad.generate_input_values(launchpad_urls[:code_subdomain])).to eq(generated)
    end

    it "returns an empty hash for a non-Launchpad URL" do
      expect(launchpad.generate_input_values(non_launchpad_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   launchpad::DEFAULT_REGEX,
        url:     generated[:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(launchpad.find_versions(url: launchpad_urls[:trunk], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(launchpad.find_versions(url: launchpad_urls[:trunk], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(launchpad.find_versions(url: launchpad_urls[:trunk], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
