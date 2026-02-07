# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Apache do
  subject(:apache) { described_class }

  let(:apache_urls) do
    {
      version_dir:                    "https://www.apache.org/dyn/closer.lua?path=abc/1.2.3/def-1.2.3.tar.gz",
      version_dir_root:               "https://www.apache.org/dyn/closer.lua?path=/abc/1.2.3/def-1.2.3.tar.gz",
      name_and_version_dir:           "https://www.apache.org/dyn/closer.lua?path=abc/def-1.2.3/ghi-1.2.3.tar.gz",
      name_dir_bin:                   "https://www.apache.org/dyn/closer.lua?path=abc/def/ghi-1.2.3-bin.tar.gz",
      name_dir_bin_no_suffix:         "https://www.apache.org/dyn/closer.lua?path=abc/def/ghi-1.2.3",
      archive_version_dir:            "https://archive.apache.org/dist/abc/1.2.3/def-1.2.3.tar.gz",
      archive_name_and_version_dir:   "https://archive.apache.org/dist/abc/def-1.2.3/ghi-1.2.3.tar.gz",
      archive_name_dir_bin:           "https://archive.apache.org/dist/abc/def/ghi-1.2.3-bin.tar.gz",
      dlcdn_version_dir:              "https://dlcdn.apache.org/abc/1.2.3/def-1.2.3.tar.gz",
      dlcdn_name_and_version_dir:     "https://dlcdn.apache.org/abc/def-1.2.3/ghi-1.2.3.tar.gz",
      dlcdn_name_dir_bin:             "https://dlcdn.apache.org/abc/def/ghi-1.2.3-bin.tar.gz",
      downloads_version_dir:          "https://downloads.apache.org/abc/1.2.3/def-1.2.3.tar.gz",
      downloads_name_and_version_dir: "https://downloads.apache.org/abc/def-1.2.3/ghi-1.2.3.tar.gz",
      downloads_name_dir_bin:         "https://downloads.apache.org/abc/def/ghi-1.2.3-bin.tar.gz",
      mirrors_version_dir:            "https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=abc/1.2.3/def-1.2.3.tar.gz",
      mirrors_version_dir_root:       "https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=/abc/1.2.3/def-1.2.3.tar.gz",
      mirrors_name_and_version_dir:   "https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=abc/def-1.2.3/ghi-1.2.3.tar.gz",
      mirrors_name_dir_bin:           "https://www.apache.org/dyn/mirrors/mirrors.cgi?action=download&filename=abc/def/ghi-1.2.3-bin.tar.gz",
    }
  end
  let(:non_apache_url) { "https://brew.sh/test" }

  let(:generated) do
    values = {
      version_dir:            {
        url:   "https://archive.apache.org/dist/abc/",
        regex: %r{href=["']?v?(\d+(?:\.\d+)+)/}i,
      },
      name_and_version_dir:   {
        url:   "https://archive.apache.org/dist/abc/",
        regex: %r{href=["']?def-v?(\d+(?:\.\d+)+)/}i,
      },
      name_dir_bin:           {
        url:   "https://archive.apache.org/dist/abc/def/",
        regex: /href=["']?ghi-v?(\d+(?:\.\d+)+)-bin\.t/i,
      },
      name_dir_bin_no_suffix: {
        url:   "https://archive.apache.org/dist/abc/def/",
        regex: /href=["']?ghi-v?(\d+(?:\.\d+)+)/i,
      },
    }
    values[:version_dir_root] = values[:version_dir]
    values[:archive_version_dir] = values[:version_dir]
    values[:archive_name_and_version_dir] = values[:name_and_version_dir]
    values[:archive_name_dir_bin] = values[:name_dir_bin]
    values[:dlcdn_version_dir] = values[:version_dir]
    values[:dlcdn_name_and_version_dir] = values[:name_and_version_dir]
    values[:dlcdn_name_dir_bin] = values[:name_dir_bin]
    values[:downloads_version_dir] = values[:version_dir]
    values[:downloads_name_and_version_dir] = values[:name_and_version_dir]
    values[:downloads_name_dir_bin] = values[:name_dir_bin]
    values[:mirrors_version_dir] = values[:version_dir]
    values[:mirrors_version_dir_root] = values[:version_dir_root]
    values[:mirrors_name_and_version_dir] = values[:name_and_version_dir]
    values[:mirrors_name_dir_bin] = values[:name_dir_bin]

    values
  end

  let(:content) do
    start_html = <<~EOS
      <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
      <html>
      <head>
        <title>Index of /dist/abc</title>
      </head>
      <body>
        <h1>Index of /dist/abc</h1>
        <pre>
          <img src="/icons/blank.gif" alt="Icon ">
          <a href="?C=N;O=D">Name</a>
          <a href="?C=M;O=A">Last modified</a>
          <a href="?C=S;O=A">Size</a>
          <a href="?C=D;O=A">Description</a>
          <hr>
          <img src="/icons/back.gif" alt="[PARENTDIR]">
          <a href="/dist/">Parent Directory</a>
                                                             -
    EOS

    end_html = <<~EOS
          <hr>
        </pre>
      </body>
      </html>
    EOS

    directories = <<~EOS
      <img src="/icons/folder.gif" alt="[DIR]"> <a href="1.2.0/">1.2.0/</a>                  2022-01-20 01:20    -
      <img src="/icons/folder.gif" alt="[DIR]"> <a href="1.2.1/">1.2.1/</a>                  2022-01-21 01:21    -
      <img src="/icons/folder.gif" alt="[DIR]"> <a href="1.2.2/">1.2.2/</a>                  2022-01-22 01:22    -
      <img src="/icons/folder.gif" alt="[DIR]"> <a href="abc-other/">abc-other/</a>         2022-01-02 01:02    -
      <img src="/icons/folder.gif" alt="[DIR]"> <a href="abc-something/">abc-something/</a> 2022-01-03 01:03    -
    EOS

    files = <<~EOS
      <img src="/icons/compressed.gif" alt="[   ]"> <a href="ghi-1.2.3-bin.tar.gz">ghi-1.2.3-bin.tar.gz</a>        2022-01-23 01:23   45M
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.3-bin.tar.gz.asc">ghi-1.2.3-bin.tar.gz.asc</a>    2022-01-23 01:23  456
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.3-bin.tar.gz.sha512">ghi-1.2.3-bin.tar.gz.sha512</a> 2022-01-23 01:23  123
      <img src="/icons/compressed.gif" alt="[   ]"> <a href="ghi-1.2.3-src.tar.gz">ghi-1.2.3-src.tar.gz</a>        2022-01-23 01:23  4.5M
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.3-src.tar.gz.asc">ghi-1.2.3-src.tar.gz.asc</a>    2022-01-23 01:23  456
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.3-src.tar.gz.sha512">ghi-1.2.3-src.tar.gz.sha512</a> 2022-01-23 01:23  123
      <img src="/icons/compressed.gif" alt="[   ]"> <a href="ghi-1.2.4-bin.tar.gz">ghi-1.2.4-bin.tar.gz</a>        2022-01-24 01:24   56M
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.4-bin.tar.gz.asc">ghi-1.2.4-bin.tar.gz.asc</a>    2022-01-24 01:24  567
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.4-bin.tar.gz.sha512">ghi-1.2.4-bin.tar.gz.sha512</a> 2022-01-24 01:24  124
      <img src="/icons/compressed.gif" alt="[   ]"> <a href="ghi-1.2.4-src.tar.gz">ghi-1.2.4-src.tar.gz</a>        2022-01-24 01:24  5.6M
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.4-src.tar.gz.asc">ghi-1.2.4-src.tar.gz.asc</a>    2022-01-24 01:24  567
      <img src="/icons/text.gif" alt="[TXT]"> <a href="ghi-1.2.4-src.tar.gz.sha512">ghi-1.2.4-src.tar.gz.sha512</a> 2022-01-24 01:24  124
    EOS

    {
      directories: start_html + directories + end_html,
      files:       start_html + files + end_html,
    }
  end

  let(:matches) do
    {
      directories: ["1.2.0", "1.2.1", "1.2.2"],
      files:       ["1.2.3", "1.2.4"],
    }
  end

  describe "::match?" do
    it "returns true for an Apache URL" do
      apache_urls.each_value { |url| expect(apache.match?(url)).to be true }
    end

    it "returns false for a non-Apache URL" do
      expect(apache.match?(non_apache_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an Apache URL" do
      apache_urls.each do |key, url|
        expect(apache.generate_input_values(url)).to eq(generated[key])
      end
    end

    it "returns an empty hash for a non-Apache URL" do
      expect(apache.generate_input_values(non_apache_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached_dirs = {
        matches: matches[:directories].to_h { |v| [v, Version.new(v)] },
        regex:   generated[:version_dir][:regex],
        url:     generated[:version_dir][:url],
        cached:  true,
      }

      {
        cached_dirs:,
        cached_files:        {
          matches: matches[:files].to_h { |v| [v, Version.new(v)] },
          regex:   generated[:name_dir_bin][:regex],
          url:     generated[:name_dir_bin][:url],
          cached:  true,
        },
        cached_dirs_default: cached_dirs.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(apache.find_versions(url: apache_urls[:version_dir], content: content[:directories]))
        .to eq(match_data[:cached_dirs])

      expect(
        apache.find_versions(
          url:     apache_urls[:name_dir_bin],
          regex:   generated[:name_dir_bin][:regex],
          content: content[:files],
        ),
      ).to eq(match_data[:cached_files])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(apache.find_versions(url: apache_urls[:version_dir], content: content[:directories]) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached_dirs])
    end

    it "returns default match_data when content is blank" do
      expect(apache.find_versions(url: apache_urls[:version_dir], content: ""))
        .to eq(match_data[:cached_dirs_default])
    end
  end
end
