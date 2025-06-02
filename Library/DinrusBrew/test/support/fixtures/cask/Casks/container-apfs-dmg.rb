cask "container-apfs-dmg" do
  version "1.2.3"
  sha256 "0630aa1145e8c3fa77aeb6ec414fee35204e90f224d6d06cb23e18a4d6112a5d"

  url "file://#{TEST_FIXTURE_DIR}/cask/container-apfs.dmg"
  homepage "https://brew.sh/container-apfs-dmg"

  app "container"
end
