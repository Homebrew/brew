# typed: false

cask "livecheck-throttle-reference" do
  version "1.2.5"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  # This cask is used in --online tests, so we use fake URLs to avoid impacting
  # real servers. The URL paths are specific enough that they'll be
  # understandable if they appear in local server logs.
  url "http://localhost/homebrew/test/cask/audit/livecheck/livecheck-throttle-reference-#{version}.dmg"
  name "Throttle"
  desc "Cask for testing throttle in a referenced cask"
  homepage "http://localhost/homebrew/test/cask/audit/livecheck/livecheck-throttle-reference"

  # The referenced check will not work, so livecheck values need to be
  # controlled using a test double.
  livecheck do
    cask "livecheck-throttle"
  end

  app "TestCask.app"
end
