cask "container-7z" do
  version "1.2.3"
  sha256 "3f9542ace85ed5f88549e2d0ea82210f8ddc87e0defbb78469d3aed719b3c964"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.7z"
  homepage "https://brew.sh/container-7z"

  depends_on formula: "unar"

  app "container"
end
