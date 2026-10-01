# typed: false

cask "invalid-depends-on-macos-and-linux" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/invalid-depends-on-macos-and-linux"

  depends_on macos: :monterey
  depends_on_arg = :linux
  depends_on depends_on_arg

  app "Caffeine.app"
end
