cask "with-many-languages" do
  version "1.2.3"

  language "en", default: true do
    sha256 :no_check
    "en"
  end
  language "cs" do
    sha256 :no_check
    "cs"
  end
  language "es-AR" do
    sha256 :no_check
    "es-AR"
  end
  language "ff" do
    sha256 :no_check
    "ff"
  end
  language "fi" do
    sha256 :no_check
    "fi"
  end
  language "gn" do
    sha256 :no_check
    "gn"
  end
  language "gu" do
    sha256 :no_check
    "gu"
  end
  language "ko" do
    sha256 :no_check
    "ko"
  end
  language "ru" do
    sha256 :no_check
    "ru"
  end
  language "sv" do
    sha256 :no_check
    "sv"
  end
  language "th" do
    sha256 :no_check
    "th"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "Caffeine"
  desc "Keep your computer awake"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
