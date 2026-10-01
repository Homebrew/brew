# typed: false

cask "depends-on-arch-arm64" do
  arch arm: "arm", intel: "intel"

  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-#{arch}-darwin.zip"
  homepage "https://brew.sh/"

  depends_on arch: :arm64

  app "Caffeine.app"
end
