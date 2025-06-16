cask "bad-checksum2" do
  version "1.2.2"
  sha256 "fab685fabf73d5a9382581ce8698fce9408f5feaa49fa10d9bc6c510493300f5"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
  homepage "https://brew.sh/container-tar-gz"

  app "container"
end
