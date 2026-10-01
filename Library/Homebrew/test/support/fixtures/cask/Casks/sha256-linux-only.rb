# typed: false

cask "sha256-linux-only" do
  arch arm: "arm", intel: "intel"

  version "1.2.3"
  sha256 arm64_linux:  "9a1c0967baa46828930ccbbc88668d1b0db07e6edf778800ed4da073c00054f8",
         x86_64_linux: "244d413861cecb3707cfbcc5c4346d5367daa827da5ea08fb3f3bc2b6276d239"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine-#{arch}.zip"
  homepage "https://brew.sh/"

  depends_on :linux

  app "Caffeine.app"
end
