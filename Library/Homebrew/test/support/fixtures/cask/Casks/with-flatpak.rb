cask "with-flatpak" do
  version "1.0"

  name "With Flatpak"
  desc "Cask with a flatpak stanza"
  homepage "https://brew.sh/with-flatpak"

  flatpak "org.gnome.Calculator"
end
