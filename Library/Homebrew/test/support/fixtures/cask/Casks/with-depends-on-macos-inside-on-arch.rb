cask "with-depends-on-macos-inside-on-arch" do
  version "1.2.3"

  # This is intentionally testing a non-rubocop compliant Cask
  # rubocop:disable Style/DisableCopsWithinSourceCodeDirective
  # rubocop:disable Cask/NoOverrides
  on_arm do
    depends_on macos: ">= :big_sur"
  end
  on_intel do
    depends_on macos: ">= :catalina"
  end
  # rubocop:enable Cask/NoOverrides
  # rubocop:enable Style/DisableCopsWithinSourceCodeDirective

  on_big_sur :or_older do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end
  on_monterey :or_newer do
    sha256 "d5b2dfbef7ea28c25f7a77cd7fa14d013d82b626db1d82e00e25822464ba19e2"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-depends-on-macos-failure"

  app "Caffeine.app"
end
