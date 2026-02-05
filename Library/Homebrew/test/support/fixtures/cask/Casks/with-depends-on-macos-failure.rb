cask "with-depends-on-macos-failure" do
  # guarantee a mismatched release
  on_big_sur :or_older do
    version "1.2.3"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end
  on_ventura :or_newer do
    version "1.2.3"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-failure"

  depends_on macos: :monterey

  app "Caffeine.app"
end
