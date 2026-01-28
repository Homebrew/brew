cask "livecheck-disabled" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  # This cask is used in --online tests, so we use fake URLs to avoid impacting
  # real servers. The URL paths are specific enough that they'll be
  # understandable if they appear in local server logs.
  url "http://localhost/homebrew/test/cask/audit/livecheck/disabled-#{version}.dmg"
  name "Disabled"
  desc "Cask for testing disabled in livecheck"
  homepage "http://localhost/homebrew/test/cask/audit/livecheck/disabled"

  disable! date: "2023-01-01", because: :discontinued

  app "TestCask.app"
end
