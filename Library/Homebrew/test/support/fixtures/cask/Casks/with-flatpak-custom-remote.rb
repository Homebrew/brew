cask "with-flatpak-custom-remote" do
  version "1.0"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "With Flatpak Custom Remote"
  desc "Cask with a flatpak stanza using custom remote"
  homepage "https://brew.sh/with-flatpak-custom-remote"

  flatpak "com.example.TestApp", remote: "fedora"
end
