# typed: false

cask "multiple-versions" do
  arch arm: "arm", intel: "intel"
  platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

  on_big_sur do
    version "1.2.0"
    sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
  end
  on_monterey :or_newer do
    version "1.2.3"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine/#{platform}/#{version}/#{arch}.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
