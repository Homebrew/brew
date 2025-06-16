cask "bad-checksum" do
  version "1.2.3"
  sha256 "badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
