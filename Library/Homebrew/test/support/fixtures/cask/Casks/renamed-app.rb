cask "renamed-app" do
  version "2.0.0"
  sha256 "9f88a6f3d8a7977cd3c116c56ee7a20a3c69e838a1d4946f815a926a57883299"

  url "file://#{TEST_FIXTURE_DIR}/cask/new-app.tar.gz"
  homepage "https://brew.sh/"

  app "NewApp.app"
end
