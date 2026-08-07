# typed: false

cask "on-linux-blocks" do
  version "1.2.3"

  on_macos do
    sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"

    app "Caffeine.app"
  end
  on_linux do
    sha256 x86_64_linux: "244d413861cecb3707cfbcc5c4346d5367daa827da5ea08fb3f3bc2b6276d239",
           arm64_linux:  "9a1c0967baa46828930ccbbc88668d1b0db07e6edf778800ed4da073c00054f8"

    url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-linux.zip"

    app_image "Caffeine.AppImage"
  end

  homepage "https://brew.sh/"
end
