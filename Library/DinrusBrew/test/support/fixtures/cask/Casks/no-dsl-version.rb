cask "no-dsl-version" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "https://brew.sh/TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
