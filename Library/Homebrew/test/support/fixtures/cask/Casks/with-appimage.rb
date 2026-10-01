# typed: false

cask "with-appimage" do
  version "1.2.3"
  sha256 "73e5daee562b151389dc3e0751579c9f69f8be05b6b057f9c058c7a6e00a10f7"

  url "file://#{TEST_FIXTURE_DIR}/cask/naked.AppImage"
  name "With AppImage"
  desc "Cask with an app_image stanza"
  homepage "https://brew.sh/with-appimage"

  app_image "naked.AppImage"
end
