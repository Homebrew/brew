cask "with-uninstall-script-app" do
  version "1.2.3"
  sha256 "5633c3a0f2e572cbf021507dec78c50998b398c343232bdfc7e26221d0a5db4d"

  url "file://#{TEST_FIXTURE_DIR}/cask/MyFancyApp.zip"
  homepage "https://brew.sh/MyFancyApp"

  app "MyFancyApp/MyFancyApp.app"

  postflight do
    File.write "#{appdir}/MyFancyApp.app/uninstall.sh", <<~SH
      #!/bin/sh
      /bin/rm -r "#{appdir}/MyFancyApp.app"
    SH
  end

  uninstall script: {
    executable:   "#{appdir}/MyFancyApp.app/uninstall.sh",
    sudo:         false,
    sudo_as_root: false,
  }
end
