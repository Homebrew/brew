cask "invalid-depends-on-arch-value" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/invalid-depends-on-arch-value"

  depends_on arch: :no_such_arch

  app "Caffeine.app"
end
