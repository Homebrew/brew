cask "livecheck-installer-manual" do
  version "1.2.3"
  sha256 "78c670559a609f5d89a5d75eee49e2a2dab48aa3ea36906d14d5f7104e483bb9"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-incl-plist.zip"
  name "With Installer Manual"
  desc "Cask with a manual installer"
  homepage "https://brew.sh/"

  livecheck do
    url :url
    strategy :extract_plist
  end

  installer manual: "Caffeine.app"
end
