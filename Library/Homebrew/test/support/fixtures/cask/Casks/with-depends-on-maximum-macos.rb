# typed: false

cask "with-depends-on-maximum-macos" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-maximum-macos"

  depends_on maximum_macos: :tahoe

  app "Caffeine.app"
end
