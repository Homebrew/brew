# typed: false

cask "sourceforge-lookalike-without-livecheck" do
  version "1.2.3"
  sha256 "a69e7357bea014f4c14ac9699274f559086844ffa46563c4619bf1addfd72ad9"

  url "https://mirror.example.com?mirror=downloads.sourceforge.net/something/Something-#{version}.dmg"
  name "Something"
  homepage "https://www.brew.sh/"

  app "Something.app"
end
