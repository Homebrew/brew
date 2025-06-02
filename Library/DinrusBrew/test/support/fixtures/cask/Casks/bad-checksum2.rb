cask "bad-checksum2" do
  version "1.2.3"
  sha256 "badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
  homepage "https://brew.sh/container-tar-gz"

  app "container"
end
