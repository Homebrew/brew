cask "with-login-items" do
  version "1.2.3"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"
  login_items "Caffeine.app"
end
