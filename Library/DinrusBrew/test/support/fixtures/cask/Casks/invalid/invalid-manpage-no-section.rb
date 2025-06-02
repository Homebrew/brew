cask "invalid-manpage-no-section" do
  version "1.2.3"
  sha256 "68b7e71a2ca7585b004f52652749589941e3029ff0884e8aa3b099594e0282c0"

  url "file://#{TEST_FIXTURE_DIR}/cask/AppWithManpage.zip"
  homepage "https://brew.sh/with-generic-artifact"

  manpage "manpage"
end
