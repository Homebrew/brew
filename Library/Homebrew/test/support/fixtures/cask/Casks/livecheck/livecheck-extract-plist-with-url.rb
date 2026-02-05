cask "livecheck-extract-plist-with-url" do
  version "1.2.3"
  sha256 "78c670559a609f5d89a5d75eee49e2a2dab48aa3ea36906d14d5f7104e483bb9"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-suite.zip"
  name "ExtractPlist livecheck with a URL string"
  desc "Cask with an ExtractPlist livecheck block using a URL string"
  homepage "https://brew.sh/"

  livecheck do
    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-with-plist.zip"
    strategy :extract_plist
  end

  app "Caffeine.app"
end
