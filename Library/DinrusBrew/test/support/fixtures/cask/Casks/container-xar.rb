cask "container-xar" do
  version "1.2.3"
  sha256 "5bb8e09a6fc630ebeaf266b1fd2d15e2ae7d32d7e4da6668a8093426fa1ba509"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.xar"
  homepage "https://brew.sh/container-xar"

  app "container"
end
