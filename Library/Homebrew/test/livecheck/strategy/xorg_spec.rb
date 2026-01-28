# frozen_string_literal: true

require "livecheck/strategy/xorg"

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
end
