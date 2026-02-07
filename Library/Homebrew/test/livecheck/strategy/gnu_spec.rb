# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Gnu do
  subject(:gnu) { described_class }

  let(:gnu_urls) do
    {
      no_version_dir: "https://ftpmirror.gnu.org/gnu/abc/abc-1.2.3.tar.gz",
      software_page:  "https://www.gnu.org/software/abc/",
      subdomain:      "https://abc.gnu.org",
      savannah:       "https://download.savannah.gnu.org/releases/abc/abc-1.2.3.tar.gz",
    }
  end
  let(:non_gnu_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      no_version_dir: {
        url:   "https://ftpmirror.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      software_page:  {
        url:   "https://ftpmirror.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      subdomain:      {
        url:   "https://ftpmirror.gnu.org/gnu/abc/",
        regex: %r{href=.*?abc[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i,
      },
      savannah:       {},
    }
  end

  # The whitespace in a real response is a bit looser and this has been
  # reformatted for the sake of brevity.
  let(:content) do
    <<~EOS
      <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
      <html>
      <head>
        <title>Index of /gnu/abc</title>
      </head>
      <body>
        <h1>Index of /gnu/abc</h1>
        <table>
          <tr>
            <th valign="top"><img src="/icons/blank.gif" alt="[ICO]"></th>
            <th><a href="?C=N;O=D">Name</a></th>
            <th><a href="?C=M;O=A">Last modified</a></th>
            <th><a href="?C=S;O=A">Size</a></th>
            <th><a href="?C=D;O=A">Description</a></th>
          </tr>
          <tr>
            <th colspan="5"><hr></th>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/back.gif" alt="[PARENTDIR]"></td>
            <td><a href="/gnu/">Parent Directory</a></td>
            <td>&nbsp;</td>
            <td align="right">  - </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/compressed.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.2.tar.gz">abc-1.2.2.tar.gz</a></td>
            <td align="right">2022-01-22 01:22  </td>
            <td align="right">3.4M</td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.2.tar.gz.sig">abc-1.2.2.tar.gz.sig</a></td>
            <td align="right">2022-01-22 01:22  </td>
            <td align="right">345 </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.3.tar.xz">abc-1.2.3.tar.xz</a></td>
            <td align="right">2022-01-23 01:23  </td>
            <td align="right">4.5M</td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.3.tar.xz.sig">abc-1.2.3.tar.xz.sig</a></td>
            <td align="right">2022-01-23 01:23  </td>
            <td align="right">456 </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <th colspan="5"><hr></th>
          </tr>
        </table>
        <address>Apache/2.4.29 (Trisquel_GNU/Linux) Server at ftp.gnu.org Port 443</address>
      </body>
      </html>

    EOS
  end

  let(:matches) { ["1.2.2", "1.2.3"] }

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

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:no_version_dir][:regex],
        url:     generated[:no_version_dir][:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(gnu.find_versions(url: gnu_urls[:no_version_dir], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(gnu.find_versions(url: gnu_urls[:no_version_dir], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(gnu.find_versions(url: gnu_urls[:no_version_dir], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
