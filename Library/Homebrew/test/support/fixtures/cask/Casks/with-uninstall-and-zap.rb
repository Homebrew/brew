# typed: false

cask "with-uninstall-and-zap" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "file://#{TEST_FIXTURE_DIR}/cask/MyFancyPkg.zip"
  homepage "https://brew.sh/fancy-pkg"

  pkg "MyFancyPkg/Fancy.pkg"

  uninstall_postflight_steps do
    remove "uninstall-postflight-marker"
  end

  uninstall quit:   "my.fancy.package.app",
            delete: "#{TEST_TMPDIR}/absolute_path"

  zap quit:    "my.fancy.package.app",
      script:  {
        executable: "MyFancyPkg/FancyUninstaller.tool",
        args:       ["--please"],
      },
      pkgutil: "my.fancy.package.*",
      delete:  "#{TEST_TMPDIR}/zap_delete_path",
      trash:   "#{TEST_TMPDIR}/zap_path"
end
