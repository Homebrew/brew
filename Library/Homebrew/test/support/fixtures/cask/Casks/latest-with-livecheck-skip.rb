cask "latest-with-livecheck-skip" do
  version :latest
  sha256 :no_check

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-livecheck-skip"

  livecheck do
    skip "no version information available"
  end

  app "Caffeine.app"
end
