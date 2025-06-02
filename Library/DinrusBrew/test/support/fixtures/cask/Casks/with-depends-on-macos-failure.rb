cask "with-depends-on-macos-failure" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  # guarantee a mismatched release
  on_mojave :or_older do
    depends_on macos: :catalina
  end
  on_catalina do
    depends_on macos: :mojave
  end
  on_big_sur :or_newer do
    depends_on macos: :catalina
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-failure"

  app "Caffeine.app"
end
