cask "with-on-system-blocks" do
  on_system :linux, macos: :sequoia_or_newer do
    version "1.2.4"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end

  url "https://brew.sh/TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
