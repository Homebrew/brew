cask "with-non-executable-binary" do
  version "1.2.3"
  sha256 "306c6ca7407560340797866e077e053627ad409277d1b9da58106fce4cf717cb"

  url "file://#{TEST_FIXTURE_DIR}/cask/naked_non_executable"
  homepage "https://brew.sh/with-binary"

  binary "naked_non_executable"
end
