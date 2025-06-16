cask "renamed-app" do
  version "1.0.0"
  sha256 "cf001ed6c81820e049dc7a353957dab8936b91f1956ee74ff0b3eb59791f1ad9"

  url "file://#{TEST_FIXTURE_DIR}/cask/old-app.tar.gz"
  homepage "https://brew.sh/"

  app "OldApp.app"
end
