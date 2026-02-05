cask "many-renames" do
  version "1.2.3"
  sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"

  url "file://#{TEST_FIXTURE_DIR}/cask/ManyArtifacts.zip"
  homepage "https://brew.sh/many-artifacts"

  rename "Foobar.app", "Foo.app"
  rename "Foo.app", "Bar.app"

  app "Bar.app"

  preflight do
    # do nothing
  end

  postflight do
    # do nothing
  end

  uninstall_preflight do
    # do nothing
  end

  uninstall_postflight do
    # do nothing
  end
end
