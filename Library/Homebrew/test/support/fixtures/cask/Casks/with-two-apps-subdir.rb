cask "with-two-apps-subdir" do
  version "1.2.3"
  sha256 "d687c22a21c02bd8f07da9302c8292b93a04df9a929e3f04d09aea6c76f75c65"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeines-subdir.zip"
  homepage "https://brew.sh/"

  app "Caffeines/Caffeine Mini.app"
  app "Caffeines/Caffeine Pro.app"
end
