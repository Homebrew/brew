cask "container-dmg" do
  version "1.2.3"
  sha256 "74d89d4fa5cef175cf43666ce11fefa3741aa1522114042ac75e656be37141a1"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.dmg"
  homepage "https://brew.sh/container-dmg"

  app "container"
end
