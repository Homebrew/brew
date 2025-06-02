cask "container-cab" do
  version "1.2.3"
  sha256 "c267f5cebb14814c8e612a8b7d2bda02aec913f869509b6f1d3883427c0f552b"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.cab"
  homepage "https://brew.sh/container-cab"

  depends_on formula: "cabextract"

  app "container"
end
