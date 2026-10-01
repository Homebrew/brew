# typed: false

cask "with-many-languages-and-invalid-sha256" do
  version "1.2.3"

  language "en", default: true do
    sha256 "not a valid shasum"
    "en"
  end
  language "cs" do
    sha256 "not a valid shasum"
    "cs"
  end
  language "es-AR" do
    sha256 "not a valid shasum"
    "es-AR"
  end
  language "ff" do
    sha256 "not a valid shasum"
    "ff"
  end
  language "fi" do
    sha256 "not a valid shasum"
    "fi"
  end
  language "gn" do
    sha256 "not a valid shasum"
    "gn"
  end
  language "gu" do
    sha256 "not a valid shasum"
    "gu"
  end
  language "ko" do
    sha256 "not a valid shasum"
    "ko"
  end
  language "ru" do
    sha256 "not a valid shasum"
    "ru"
  end
  language "sv" do
    sha256 "not a valid shasum"
    "sv"
  end
  language "th" do
    sha256 "not a valid shasum"
    "th"
  end

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  name "Caffeine"
  desc "Keep your computer awake"
  homepage "https://brew.sh/"

  app "Caffeine.app"
end
