cask "livecheck-extract-plist" do
  version "1.2.3"
  sha256 "78c670559a609f5d89a5d75eee49e2a2dab48aa3ea36906d14d5f7104e483bb9"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-with-plist.zip"
  name "ExtractPlist livecheck"
  desc "Cask with an ExtractPlist livecheck block"
  homepage "https://brew.sh/"

  livecheck do
    url :url
    strategy :extract_plist
  end

  app "Caffeine.app"
end
