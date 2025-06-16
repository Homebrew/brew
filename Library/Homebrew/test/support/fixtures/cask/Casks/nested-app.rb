cask "nested-app" do
  version "1.2.3"
  sha256 "1866dfa833b123bb8fe7fa7185ebf24d28d300d0643d75798bc23730af734216"

  url "file://#{TEST_FIXTURE_DIR}/cask/NestedApp.dmg.zip"
  homepage "https://brew.sh/nested-app"

  container nested: "NestedApp.dmg"

  app "MyNestedApp.app"
end
