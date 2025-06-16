cask "container-bzip2" do
  version "1.2.3"
  sha256 "eaf67b3a62cb9275f96e45d05c70b94bef9ef1dae344083e93eda6b0b388a61c"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.bz2"
  homepage "https://brew.sh/container-bzip2"

  app "container"
end
