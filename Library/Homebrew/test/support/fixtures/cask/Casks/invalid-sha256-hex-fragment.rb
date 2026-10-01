# typed: false

cask "invalid-sha256-hex-fragment" do
  version "1.2.3"
  sha256 "a\nZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "Caffeine"
  desc "Cask for testing a sha256 whose hexadecimal run is far shorter than 64"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
