cask "sha256-os" do
  arch arm: "arm", intel: "intel"
  os macos: "darwin", linux: "linux"

  version "1.2.3"
  sha256 arm:          "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94",
         intel:        "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b",
         x86_64_linux: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b",
         arm64_linux:  "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-#{arch}-#{os}.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
