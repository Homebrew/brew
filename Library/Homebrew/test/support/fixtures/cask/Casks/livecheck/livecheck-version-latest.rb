cask "livecheck-version-latest" do
  version :latest
  sha256 :no_check

  # This cask is used in --online tests, so we use fake URLs to avoid impacting
  # real servers. The URL paths are specific enough that they'll be
  # understandable if they appear in local server logs.
  url "http://localhost/homebrew/test/cask/audit/livecheck/version-latest.dmg"
  name "Version Latest"
  desc "Cask for testing a latest version in livecheck"
  homepage "http://localhost/homebrew/test/cask/audit/livecheck/version-latest"

  app "TestCask.app"
end
