cask "with-autodetected-manpage-section" do
  version "1.2.3"
  sha256 "1f078d5fbbaf44b05d0389b14a15f6704e0e5f8f663bc38153a4d685e38baad5"

  url "file://#{TEST_FIXTURE_DIR}/cask/AppWithManpage.zip"
  homepage "https://brew.sh/with-autodetected-manpage-section"

  manpage "manpage.1"
  manpage "gzpage.1.gz"
end
