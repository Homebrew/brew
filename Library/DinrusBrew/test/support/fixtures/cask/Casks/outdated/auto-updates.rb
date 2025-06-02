cask "auto-updates" do
  version "2.57"
  sha256 "5633c3a0f2e572cbf021507dec78c50998b398c343232bdfc7e26221d0a5db4d"

  url "file://#{TEST_FIXTURE_DIR}/cask/MyFancyApp.zip"
  homepage "https://brew.sh/MyFancyApp"

  auto_updates true

  app "MyFancyApp/MyFancyApp.app"
end
