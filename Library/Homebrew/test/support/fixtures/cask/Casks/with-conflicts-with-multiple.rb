# typed: false

cask "with-conflicts-with-multiple" do
  version "1.2.3"
  sha256 "8dd95f83a6cbf67dd73f003c476ea38a5aab367e3af8f56d485c0ff9017b6ee5"

  on_macos do
    conflicts_with cask: "macos-caffeine"
  end
  on_linux do
    conflicts_with cask: "linux-caffeine"
  end

  url "https://brew.sh/ConflictsWith-1.2.3.dmg"
  name "ConflictsWith"
  homepage "https://brew.sh/"

  conflicts_with cask: "local-caffeine"
  conflicts_with cask: ["local-caffeine", "with-caffeine"]
end
