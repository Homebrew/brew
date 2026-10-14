# typed: false

cask "with-appimage" do
  version "1.2.3"
  sha256 "99b62217e2f08f58b151d9163b8b45d5232a5db6550da7e4718b0c7290f414f1"

  url "file://#{TEST_FIXTURE_DIR}/cask/naked.AppImage"
  name "With AppImage"
  desc "Cask with an app_image stanza"
  homepage "https://brew.sh/with-appimage"

  depends_on :linux

  app_image "naked.AppImage"
end
