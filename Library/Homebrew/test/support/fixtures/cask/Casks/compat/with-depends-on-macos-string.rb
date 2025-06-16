cask "with-depends-on-macos-string" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-string"

  depends_on macos: MacOS.version.to_s

  app "Caffeine.app"
end
