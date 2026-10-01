# typed: false

cask "with-languages" do
  version "1.2.3"

  language "zh" do
    sha256 "fab685fabf73d5a9382581ce8698fce9408f5feaa49fa10d9bc6c510493300f5"
    app "Container.app"
    "zh-CN"
  end
  language "en-US", default: true do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
    app "Caffeine.app"
    "en-US"
  end

  archive = (language == "zh-CN") ? "container.tar.gz" : "caffeine.zip"
  url "file://#{TEST_FIXTURE_DIR}/cask/#{archive}"
  name "Caffeine"
  homepage "https://brew.sh/"

  depends_on macos: :big_sur
end
