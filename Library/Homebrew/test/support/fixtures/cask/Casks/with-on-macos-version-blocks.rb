cask "with-on-macos-version-blocks" do
  on_big_sur :or_older do
    version "1.2.3"
    sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
  end
  on_monterey do
    version "1.2.4"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end
  on_ventura :or_newer do
    version "1.2.5"
    sha256 "306c6ca7407560340797866e077e053627ad409277d1b9da58106fce4cf717cb"
  end

  url "https://brew.sh/TestCask-#{version}.dmg"
  homepage "https://brew.sh/"

  app "TestCask.app"
end
