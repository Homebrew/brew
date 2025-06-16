cask "with-auto-updates" do
  version "1.0"
  sha256 "e5be907a51cd0d5b128532284afe1c913608c584936a5e55d94c75a9f48c4322"

  url "https://brew.sh/autoupdates_#{version}.zip"
  name "AutoUpdates"
  homepage "https://brew.sh/autoupdates"

  auto_updates true

  app "AutoUpdates.app"
end
