cask "with-binary" do
  version "1.2.3"
  sha256 "d5b2dfbef7ea28c25f7a77cd7fa14d013d82b626db1d82e00e25822464ba19e2"

  url "file://#{TEST_FIXTURE_DIR}/cask/AppWithBinary.zip"
  name "With Binary"
  desc "Cask with a binary stanza"
  homepage "https://brew.sh/with-binary"

  app "App.app"
  binary "binary"
end
