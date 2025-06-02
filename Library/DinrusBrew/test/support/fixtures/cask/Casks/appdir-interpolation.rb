cask "appdir-interpolation" do
  version "2.61"
  sha256 "e44ffa103fbf83f55c8d0b1bea309a43b2880798dae8620b1ee8da5e1095ec68"

  url "file://#{TEST_FIXTURE_DIR}/cask/transmission-2.61.dmg"
  homepage "https://brew.sh/appdir-interpolation"

  binary "#{appdir}/some/path"
end
