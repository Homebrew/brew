# frozen_string_literal: true

require "livecheck/strategy/gnu"

describe Homebrew::Livecheck::Strategy::Gnu do
  subject(:gnu) { described_class }

  let(:gnu_urls) do
    {
      no_version_dir: "https://ftp.gnu.org/gnu/abc/abc-1.2.3.tar.gz",
      software_page:  "https://www.gnu.org/software/abc/",
      subdomain:      "https://abc.gnu.org",
      savannah:       "https://download.savannah.gnu.org/releases/abc/abc-1.2.3.tar.gz",
    }
  end
  let(:non_gnu_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      no_version_dir: {
        url:   "https://ftp.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      software_page:  {
        url:   "https://ftp.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      subdomain:      {
        url:   "https://ftp.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      savannah:       {},
    }
  end

  describe "::match?" do
    it "returns true for a [non-Savannah] GNU URL" do
      expect(gnu.match?(gnu_urls[:no_version_dir])).to be true
      expect(gnu.match?(gnu_urls[:software_page])).to be true
      expect(gnu.match?(gnu_urls[:subdomain])).to be true
    end

    it "returns false for a Savannah GNU URL" do
      expect(gnu.match?(gnu_urls[:savannah])).to be false
    end

    it "returns false for a non-GNU URL (not nongnu.org)" do
      expect(gnu.match?(non_gnu_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a [non-Savannah] GNU URL" do
      expect(gnu.generate_input_values(gnu_urls[:no_version_dir])).to eq(generated[:no_version_dir])
      expect(gnu.generate_input_values(gnu_urls[:software_page])).to eq(generated[:software_page])
      expect(gnu.generate_input_values(gnu_urls[:subdomain])).to eq(generated[:subdomain])
    end

    it "returns an empty hash for a Savannah GNU URL" do
      expect(gnu.generate_input_values(gnu_urls[:savannah])).to eq(generated[:savannah])
    end

    it "returns an empty hash for a non-GNU URL (not nongnu.org)" do
      expect(gnu.generate_input_values(non_gnu_url)).to eq({})
    end
  end
end
