# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Sourceforge do
  subject(:sourceforge) { described_class }

  let(:sourceforge_urls) do
    {
      typical:       "https://downloads.sourceforge.net/project/abc/def-1.2.3.tar.gz",
      rss:           "https://sourceforge.net/projects/abc/rss",
      rss_with_path: "https://sourceforge.net/projects/abc/rss?path=/def",
    }
  end
  let(:non_sourceforge_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      typical: {
        url:   "https://sourceforge.net/projects/abc/rss",
        regex: %r{url=.*?/abc/files/.*?[-_/](\d+(?:[-.]\d+)+)[-_/%.]}i,
      },
      rss:     {
        regex: %r{url=.*?/abc/files/.*?[-_/](\d+(?:[-.]\d+)+)[-_/%.]}i,
      },
    }
  end

  let(:content) do
    <<~EOS
      <?xml version="1.0" encoding="utf-8"?>
      <rss xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:files="https://sourceforge.net/api/files.rdf#" xmlns:media="http://video.search.yahoo.com/mrss/" xmlns:doap="http://usefulinc.com/ns/doap#" xmlns:sf="https://sourceforge.net/api/sfelements.rdf#" version="2.0">
        <channel xmlns:files="https://sourceforge.net/api/files.rdf#" xmlns:media="http://video.search.yahoo.com/mrss/" xmlns:doap="http://usefulinc.com/ns/doap#" xmlns:sf="https://sourceforge.net/api/sfelements.rdf#">
          <title>abc</title>
          <link>https://sourceforge.net</link>
          <description><![CDATA[Files from abc Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.]]></description>
          <pubDate>Sun, 24 Jan 2022 01:24:56 UT</pubDate>
          <managingEditor>noreply@sourceforge.net (SourceForge.net)</managingEditor>
          <docs>http://blogs.law.harvard.edu/tech/rss</docs>
          <item>
            <title><![CDATA[/abc/def-1.2.3.tar.gz]]></title>
            <link>https://sourceforge.net/projects/abc/files/def-1.2.3.tar.gz/download</link>
            <guid>https://sourceforge.net/projects/abc/files/def-1.2.3.tar.gz/download</guid>
            <pubDate>Mon, 23 Jan 2022 01:23:45 UT</pubDate>
            <description><![CDATA[/abc/def-1.2.3.tar.gz]]></description>
            <files:sf-file-id xmlns:files="https://sourceforge.net/api/files.rdf#">537951</files:sf-file-id>
            <files:extra-info xmlns:files="https://sourceforge.net/api/files.rdf#">POSIX tar archive</files:extra-info>
            <media:content xmlns:media="http://video.search.yahoo.com/mrss/" type="application/x-gzip" url="https://sourceforge.net/projects/abc/files/def-1.2.3.tar.gz/download" filesize="123456"><media:hash algo="md5">01234567890abcdef01234567890abcd</media:hash></media:content>
          </item>
        </channel>
      </rss>
    EOS
  end

  let(:matches) { ["1.2.3"] }

  describe "::match?" do
    it "returns true for a SourceForge URL" do
      expect(sourceforge.match?(sourceforge_urls[:typical])).to be true
      expect(sourceforge.match?(sourceforge_urls[:rss])).to be true
      expect(sourceforge.match?(sourceforge_urls[:rss_with_path])).to be true
    end

    it "returns false for a non-SourceForge URL" do
      expect(sourceforge.match?(non_sourceforge_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an Apache URL" do
      expect(sourceforge.generate_input_values(sourceforge_urls[:typical])).to eq(generated[:typical])
      expect(sourceforge.generate_input_values(sourceforge_urls[:rss])).to eq(generated[:rss])
      expect(sourceforge.generate_input_values(sourceforge_urls[:rss_with_path])).to eq(generated[:rss])
    end

    it "returns an empty hash for a non-Apache URL" do
      expect(sourceforge.generate_input_values(non_sourceforge_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:typical][:regex],
        url:     generated[:typical][:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(sourceforge.find_versions(url: sourceforge_urls[:typical], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(sourceforge.find_versions(url: sourceforge_urls[:typical], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(sourceforge.find_versions(url: sourceforge_urls[:typical], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
