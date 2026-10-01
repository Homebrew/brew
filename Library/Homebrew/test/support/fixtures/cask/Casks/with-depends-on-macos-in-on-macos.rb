# typed: false

cask "with-depends-on-macos-in-on-macos" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  on_macos do
    depends_on macos: :monterey
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-in-on-macos"

  binary "caffeine"
end
