cask "container-pkg" do
  version "1.2.3"
  sha256 "611c50c8a2a2098951d2cd0fd54787ed81b92cd97b4b08bd7cba17f1e1d8e40b"

  url "file://#{TEST_FIXTURE_DIR}/cask/container.pkg"
  homepage "https://brew.sh/container-pkg"
end
