cask "on-linux-arch" do
  version "1.0.0"
  sha256 :no_check

  url "https://brew.sh/"
  name "On Linux Arch"
  desc "Cask with on_linux architecture dependency"
  homepage "https://brew.sh/"

  on_linux do
    depends_on arch: :intel
  end

  app "On Linux Arch.app"
end
