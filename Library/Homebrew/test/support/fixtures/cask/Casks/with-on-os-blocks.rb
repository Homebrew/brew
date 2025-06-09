cask "with-on-os-blocks" do
  on_linux do
    version "1.2.3"
    sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
  end
  on_macos do
    version "1.2.4"
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
  end

  url "https://brew.sh/TestCask-#{version}.zip"
  homepage "https://brew.sh/"

  binary "testcask"
end
