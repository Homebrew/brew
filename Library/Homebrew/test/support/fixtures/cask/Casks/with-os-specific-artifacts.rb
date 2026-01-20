cask "with-os-specific-artifacts" do
  version "1.2.3"

  on_macos do
    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

    app "Caffeine.app"
  end

  on_linux do
    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

    app "Caffeine.app"
  end

  name "With OS-specific artifacts"
  homepage "https://brew.sh/"
end
