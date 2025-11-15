cask "with-flatpak-custom-remote" do
  version "1.0"

  name "With Flatpak Custom Remote"
  desc "Cask with a flatpak stanza using custom remote"
  homepage "https://brew.sh/with-flatpak-custom-remote"

  flatpak "com.example.TestApp", remote: "fedora"
end
