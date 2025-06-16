cask "with-pkgutil-zap" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "file://#{TEST_FIXTURE_DIR}/cask/MyFancyPkg.zip"
  homepage "https://brew.sh/fancy-pkg"

  pkg "Fancy.pkg"

  zap launchctl: "my.fancy.package.service",
      kext:      "my.fancy.package.kernelextension",
      pkgutil:   "my.fancy.package.*"
end
