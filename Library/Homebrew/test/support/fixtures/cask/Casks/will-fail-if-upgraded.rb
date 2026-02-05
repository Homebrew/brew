cask "will-fail-if-upgraded" do
  version "1.2.3"
  sha256 "5e96aeb365aa8fabd51bb0d85f5f2bfe0135d392bb2f4120aa6b8171415906da"

  url "file://#{TEST_FIXTURE_DIR}/cask/transmission-2.61.zip"
  homepage "https://brew.sh/"

  app "container"
end
