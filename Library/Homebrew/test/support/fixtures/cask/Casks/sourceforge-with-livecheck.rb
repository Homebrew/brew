cask "sourceforge-with-livecheck" do
  version "1.2.3"

  url "https://downloads.sourceforge.net/something/Something-1.2.3.dmg"
  homepage "https://sourceforge.net/projects/something/"

  livecheck do
    url "https://sourceforge.net/projects/something/rss"
  end
end
