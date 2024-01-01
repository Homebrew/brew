cask "livecheck-version-latest-reference" do
  version :latest
  sha256 :no_check

  # This cask is used in --online tests, so we use fake URLs to avoid impacting
  # real servers. The URL paths are specific enough that they'll be
  # understandable if they appear in local server logs.
  url "http://localhost/homebrew/test/cask/audit/livecheck/version-latest.dmg"
  name "Version Latest Reference"
  desc "Cask for testing a livecheck reference to a cask where version is :latest"
  homepage "http://localhost/homebrew/test/cask/audit/livecheck/version-latest"

  livecheck do
    cask "livecheck/livecheck-version-latest"
  end

  app "TestCask.app"
end
