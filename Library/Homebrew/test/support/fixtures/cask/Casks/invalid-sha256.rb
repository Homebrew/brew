# typed: false

cask "invalid-sha256" do
  version "1.2.3"
  sha256 "not a valid shasum"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "Caffeine"
  desc "Cask for testing an invalid sha256"
  homepage "https://brew.sh/"

  depends_on macos: :big_sur

  app "Caffeine.app"
end
