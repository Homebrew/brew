cask "with-appimage" do
  version "1.2.3"
  sha256 "d5b2dfbef7ea28c25f7a77cd7fa14d013d82b626db1d82e00e25822464ba19e2"

  url "file://#{TEST_FIXTURE_DIR}/cask/AppWithBinary.zip"
  name "With AppImage"
  desc "Cask with an appimage stanza"
  homepage "https://brew.sh/with-appimage"

  appimage "binary"
end
