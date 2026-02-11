cask "noscribe" do
  version "0.7.0"
  sha256 "51ddc35a937fc04472dedc40a29d0b1131c12441652b78f6ac5b260f34f30779"

  url "https://drive.switch.ch/index.php/s/EIVup04qkSHb54j/download?path=%2FnoScribe%20vers.%20#{version.major_minor}%2FmacOS%2FApple%20Silicon&files=noScribe_#{version}_arm64.dmg",
      verified: "drive.switch.ch/"
  name "noScribe"
  desc "AI-based transcription tool for qualitative research"
  homepage "https://github.com/kaixxx/noScribe"

  # This line is crucial for an ARM-only submission
  depends_on arch: :arm64

  app "noScribe.app"

  zap trash: [
    "~/Library/Application Support/noscribe",
    "~/Library/Preferences/com.noscribe.plist",
    "~/Library/Saved Application State/com.noscribe.savedState",
  ]
end
