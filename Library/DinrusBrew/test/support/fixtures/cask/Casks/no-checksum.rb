cask "no-checksum" do
  version "1.2.3"
  sha256 :no_check

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
