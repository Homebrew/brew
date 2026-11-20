# typed: false

cask "with-desktop-entry" do
  version "1.2.3"
  sha256 "306c6ca7407560340797866e077e053627ad409277d1b9da58106fce4cf717cb"

  url "file://#{TEST_FIXTURE_DIR}/cask/naked_executable"
  name "With Desktop Entry"
  desc "Cask with a desktop_entry stanza"
  homepage "https://brew.sh/with-desktop-entry"

  depends_on :linux
  container type: :naked

  desktop_entry "Foo/share/applications/foo.desktop"
end
