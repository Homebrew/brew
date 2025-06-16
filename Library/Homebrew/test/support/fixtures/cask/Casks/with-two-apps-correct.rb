cask "with-two-apps-correct" do
  version "1.2.3"
  sha256 "3178fbfd1ea5d87a2a0662a4eb599ebc9a03888e73f37538d9f3f6ee69d2368e"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeines.zip"
  homepage "https://brew.sh/"

  app "Caffeine Mini.app"
  app "Caffeine Pro.app"
end
