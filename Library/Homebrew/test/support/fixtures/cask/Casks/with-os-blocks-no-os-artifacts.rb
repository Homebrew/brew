cask "with-os-blocks-no-os-artifacts" do
  version "1.2.3"

  on_macos do
    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

    binary "caffeine"
  end

  on_linux do
    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
    sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

    binary "caffeine"
  end

  name "With OS blocks but no OS-specific artifacts"
  homepage "https://brew.sh/"
end
