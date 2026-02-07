# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Bitbucket do
  subject(:bitbucket) { described_class }

  let(:bitbucket_urls) do
    {
      get:       "https://bitbucket.org/abc/def/get/1.2.3.tar.gz",
      downloads: "https://bitbucket.org/abc/def/downloads/ghi-1.2.3.tar.gz",
    }
  end
  let(:non_bitbucket_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      get:       {
        url:   "https://bitbucket.org/abc/def/downloads/?tab=tags&iframe=true&spa=0",
        regex: /<td[^>]*?class="name"[^>]*?>\s*v?(\d+(?:\.\d+)+)\s*?</im,
      },
      downloads: {
        url:   "https://bitbucket.org/abc/def/downloads/?iframe=true&spa=0",
        regex: /href=.*?ghi-v?(\d+(?:\.\d+)+)\.t/i,
      },
    }
  end

  # This example HTML omits table columns for the sake of brevity.
  let(:content) do
    <<~EOS
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>abc / def / Downloads &mdash; Bitbucket</title>
        </head>
        <body>
          <table id="uploaded-files">
          <thead>
            <tr>
              <th class="name">Name</th>
              <th class="size">Size</th>
              <th class="date">Date</th>
            </tr>
          </thead>
          <tbody>
            <tr class="iterable-item" id="download-12345678">
              <td class="name">
                <a href="/abc/def/downloads/ghi-1.2.3.tar.gz">ghi-1.2.3.tar.gz</a>
              </td>
              <td class="size">4.5\u00A0MB</td>
              <td class="date">
                <div>
                  <time datetime="2022-01-23T01:23:45.678901" data-title="true">2022-01-23</time>
                </div>
              </td>
            </tr>
            <tr class="iterable-item" id="download-12345677">
              <td class="name">
                <a href="/abc/def/downloads/ghi-1.2.2.tar.gz">ghi-1.2.2.tar.gz</a>
              </td>
              <td class="size">3.4\u00A0MB</td>
              <td class="date">
                <div>
                  <time datetime="2022-01-22T01:22:34.567890" data-title="true">2022-01-22</time>
                </div>
              </td>
            </tr>
            <tr class="iterable-item" id="download-12345676">
              <td class="name">
                <a href="/abc/def/downloads/ghi-1.2.1.tar.gz">ghi-1.2.1.tar.gz</a>
              </td>
              <td class="size">2.3\u00A0MB</td>
              <td class="date">
                <div>
                  <time datetime="2022-01-21T01:21:23.456789" data-title="true">2022-01-21</time>
                </div>
              </td>
            </tr>
        </body>
      </html>
    EOS
  end

  let(:matches) { ["1.2.3", "1.2.2", "1.2.1"] }

  describe "::match?" do
    it "returns true for a Bitbucket URL" do
      expect(bitbucket.match?(bitbucket_urls[:get])).to be true
      expect(bitbucket.match?(bitbucket_urls[:downloads])).to be true
    end

    it "returns false for a non-Bitbucket URL" do
      expect(bitbucket.match?(non_bitbucket_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a Bitbucket URL" do
      expect(bitbucket.generate_input_values(bitbucket_urls[:get])).to eq(generated[:get])
      expect(bitbucket.generate_input_values(bitbucket_urls[:downloads])).to eq(generated[:downloads])
    end

    it "returns an empty hash for a non-Bitbucket URL" do
      expect(bitbucket.generate_input_values(non_bitbucket_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:downloads][:regex],
        url:     generated[:downloads][:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(bitbucket.find_versions(url: bitbucket_urls[:downloads], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(bitbucket.find_versions(url: bitbucket_urls[:downloads], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(bitbucket.find_versions(url: bitbucket_urls[:downloads], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
