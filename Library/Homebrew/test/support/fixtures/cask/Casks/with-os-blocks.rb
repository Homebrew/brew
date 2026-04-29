# typed: false

cask "with-os-blocks" do
  version "1.0"

  on_macos do
    sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

    url "https://brew.sh/test-#{version}.dmg"

    app "TestCask.app"
  end

  on_linux do
    sha256 "306c6ca7407560340797866e077e053627ad409277d1b9da58106fce4cf717cb"

    url "https://brew.sh/test-#{version}.tar.gz"

    binary "TestCask"
  end

  name "With OS Blocks"
  desc "Cask with on_macos and on_linux blocks"
  homepage "https://brew.sh/"
end
