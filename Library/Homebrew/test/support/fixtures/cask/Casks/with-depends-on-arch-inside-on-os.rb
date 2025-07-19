cask "with-depends-on-arch-inside-on-os" do
  version "1.2.3"

  on_catalina :or_older do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end
  on_big_sur do
    sha256 "d5b2dfbef7ea28c25f7a77cd7fa14d013d82b626db1d82e00e25822464ba19e2"

    depends_on arch: :x86_64
  end
  on_monterey do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end
  on_ventura do
    sha256 "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890"
  end
  on_sonoma :or_newer do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-failure"

  app "Caffeine.app"
end
