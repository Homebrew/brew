# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Apache do
  subject(:apache) { described_class }

  let(:apache_urls) do
    {
      version_dir:                    "https://www.apache.org/dyn/closer.lua?path=abc/1.2.3/def-1.2.3.tar.gz",
      version_dir_root:               "https://www.apache.org/dyn/closer.lua?path=/abc/1.2.3/def-1.2.3.tar.gz",
      name_and_version_dir:           "https://www.apache.org/dyn/closer.lua?path=abc/def-1.2.3/ghi-1.2.3.tar.gz",
      name_dir_bin:                   "https://www.apache.org/dyn/closer.lua?path=abc/def/ghi-1.2.3-bin.tar.gz",
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
      version_dir:          {
        url:   "https://archive.apache.org/dist/abc/",
        regex: %r{href=["']?v?(\d+(?:\.\d+)+)/}i,
      },
      name_and_version_dir: {
        url:   "https://archive.apache.org/dist/abc/",
        regex: %r{href=["']?def-v?(\d+(?:\.\d+)+)/}i,
      },
      name_dir_bin:         {
        url:   "https://archive.apache.org/dist/abc/def/",
        regex: /href=["']?ghi-v?(\d+(?:\.\d+)+)-bin\.t/i,
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
end
