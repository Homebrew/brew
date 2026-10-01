# typed: false

cask "invalid-sha256-newline" do
  version "1.2.3"
  sha256 "0123456789abcdef0123456789abcde\n0123456789abcdef0123456789abcdef"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "Caffeine"
  desc "Cask for testing a sha256 that is the right length but not hexadecimal"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
