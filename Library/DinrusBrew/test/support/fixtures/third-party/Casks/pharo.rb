cask "pharo" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "https://brew.sh/ThirdParty-#{version}.dmg"
  name "Pharo"
  desc "Cask from a third-party tap"
  homepage "https://brew.sh/"

  app "ThirdParty.app"
end
