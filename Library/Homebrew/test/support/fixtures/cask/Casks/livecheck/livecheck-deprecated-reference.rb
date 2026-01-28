cask "livecheck-deprecated-reference" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  # This cask is used in --online tests, so we use fake URLs to avoid impacting
  # real servers. The URL paths are specific enough that they'll be
  # understandable if they appear in local server logs.
  url "http://localhost/homebrew/test/cask/audit/livecheck/deprecated-#{version}.dmg"
  name "Deprecated Reference"
  desc "Cask for testing a livecheck reference to a deprecated cask"
  homepage "http://localhost/homebrew/test/cask/audit/livecheck/deprecated"

  livecheck do
    cask "livecheck-deprecated"
  end

  app "TestCask.app"
end
