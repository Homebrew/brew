cask "devmate-with-livecheck" do
  version "1.0"
  sha256 "a69e7357bea014f4c14ac9699274f559086844ffa46563c4619bf1addfd72ad9"

  url "https://dl.devmate.com/com.my.fancyapp/app_#{version}.zip"
  name "DevMate"
  homepage "https://www.brew.sh/"

  livecheck do
    url "https://updates.devmate.com/com.my.fancyapp.app.xml"
  end

  app "DevMate.app"
end
