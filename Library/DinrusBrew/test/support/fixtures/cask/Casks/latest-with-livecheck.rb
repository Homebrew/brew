cask "latest-with-livecheck" do
  version :latest
  sha256 :no_check

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/with-livecheck"

  livecheck do
    url "https://brew.sh/with-livecheck/changelog"
  end

  app "Caffeine.app"
end
