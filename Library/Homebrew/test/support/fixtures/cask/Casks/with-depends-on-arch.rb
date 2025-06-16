cask "with-depends-on-arch" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-arch"

  # covers all known hardware; always succeeds
  depends_on arch: [:intel, :arm64]

  app "Caffeine.app"
end
