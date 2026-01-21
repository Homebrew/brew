cask "nested-app" do
  version "1.2.3"
  sha256 "69034d000fabf804a6e140c8c632f8ce8a3bf303f5f7db2fb0cd86e3aeed9e67"

  url "file://#{TEST_FIXTURE_DIR}/cask/NestedApp.zip.tar.gz"
  homepage "https://brew.sh/nested-app"

  container nested: "NestedApp.zip"

  app "MyNestedApp.app"
end
