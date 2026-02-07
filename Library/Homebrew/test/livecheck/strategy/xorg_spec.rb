# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Xorg do
  subject(:xorg) { described_class }

  let(:xorg_urls) do
    {
      app:         "https://www.x.org/archive/individual/app/abc-1.2.3.tar.bz2",
      font:        "https://www.x.org/archive/individual/font/abc-1.2.3.tar.bz2",
      lib:         "https://www.x.org/archive/individual/lib/libabc-1.2.3.tar.bz2",
      ftp_lib:     "https://ftp.x.org/archive/individual/lib/libabc-1.2.3.tar.bz2",
      pub_doc:     "https://www.x.org/pub/individual/doc/abc-1.2.3.tar.bz2",
      freedesktop: "https://xorg.freedesktop.org/archive/individual/util/abc-1.2.3.tar.xz",
      mesa:        "https://archive.mesa3d.org/mesa-1.2.3.tar.xz",
    }
  end
  let(:non_xorg_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      app:         {
        url:   "https://www.x.org/archive/individual/app/",
        regex: /href=.*?abc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      font:        {
        url:   "https://www.x.org/archive/individual/font/",
        regex: /href=.*?abc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      lib:         {
        url:   "https://www.x.org/archive/individual/lib/",
        regex: /href=.*?libabc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      ftp_lib:     {
        url:   "https://ftp.x.org/archive/individual/lib/",
        regex: /href=.*?libabc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      pub_doc:     {
        url:   "https://www.x.org/archive/individual/doc/",
        regex: /href=.*?abc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      freedesktop: {
        url:   "https://xorg.freedesktop.org/archive/individual/util/",
        regex: /href=.*?abc[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
      mesa:        {
        url:   "https://archive.mesa3d.org/",
        regex: /href=.*?mesa[._-]v?(\d+(?:\.\d+)+)\.t/i,
      },
    }
  end

  let(:content) do
    <<~EOS
      <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
      <html>
      <head>
        <title>Index of /archive/individual/app</title>
      </head>
      <body>
        <h1>Index of /archive/individual/app</h1>
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
            <td><a href="/archive/individual/">Parent Directory</a></td>
            <td>&nbsp;</td>
            <td align="right">  - </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.2.tar.xz">abc-1.2.2.tar.xz</a></td>
            <td align="right">2022-01-22 01:22  </td>
            <td align="right">122K</td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.2.tar.xz.sha1">abc-1.2.2.tar.xz.sha1</a></td>
            <td align="right">2022-01-22 01:22  </td>
            <td align="right"> 12 </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.3.tar.xz">abc-1.2.3.tar.xz</a></td>
            <td align="right">2022-01-23 01:23  </td>
            <td align="right">123K</td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td>
            <td><a href="abc-1.2.3.tar.xz.sha1">abc-1.2.3.tar.xz.sha1</a></td>
            <td align="right">2022-01-23 01:23  </td>
            <td align="right"> 12 </td>
            <td>&nbsp;</td>
          </tr>
          <tr>
            <th colspan="5"><hr></th>
          </tr>
        </table>
        <address>Apache/2.4.38 (Debian) Server at www.x.org Port 443</address>
      </body>
      </html>
    EOS
  end

  let(:matches) { ["1.2.2", "1.2.3"] }

  describe "::match?" do
    it "returns true for an X.Org URL" do
      expect(xorg.match?(xorg_urls[:app])).to be true
      expect(xorg.match?(xorg_urls[:font])).to be true
      expect(xorg.match?(xorg_urls[:lib])).to be true
      expect(xorg.match?(xorg_urls[:ftp_lib])).to be true
      expect(xorg.match?(xorg_urls[:pub_doc])).to be true
      expect(xorg.match?(xorg_urls[:freedesktop])).to be true
      expect(xorg.match?(xorg_urls[:mesa])).to be true
    end

    it "returns false for a non-X.Org URL" do
      expect(xorg.match?(non_xorg_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an X.org URL" do
      expect(xorg.generate_input_values(xorg_urls[:app])).to eq(generated[:app])
      expect(xorg.generate_input_values(xorg_urls[:font])).to eq(generated[:font])
      expect(xorg.generate_input_values(xorg_urls[:lib])).to eq(generated[:lib])
      expect(xorg.generate_input_values(xorg_urls[:ftp_lib])).to eq(generated[:ftp_lib])
      expect(xorg.generate_input_values(xorg_urls[:pub_doc])).to eq(generated[:pub_doc])
      expect(xorg.generate_input_values(xorg_urls[:freedesktop])).to eq(generated[:freedesktop])
      expect(xorg.generate_input_values(xorg_urls[:mesa])).to eq(generated[:mesa])
    end

    it "returns an empty hash for a non-X.org URL" do
      expect(xorg.generate_input_values(non_xorg_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      base = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:app][:regex],
        url:     generated[:app][:url],
      }

      {
        fetched:        base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    before { xorg.instance_variable_set(:@page_data, {}) }

    it "finds versions in fetched content" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: })

      expect(xorg.find_versions(url: xorg_urls[:app])).to eq(match_data[:fetched])
    end

    it "finds versions in cached content" do
      xorg.instance_variable_set(
        :@page_data,
        { generated[:app][:url] => content },
      )
      expect(xorg.find_versions(url: xorg_urls[:app])).to eq(match_data[:cached])
    end

    it "finds versions in provided content" do
      expect(xorg.find_versions(url: xorg_urls[:app], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(xorg.find_versions(url: xorg_urls[:app], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(xorg.find_versions(url: xorg_urls[:app], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
