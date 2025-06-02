cask "with-caveats" do
  version "1.2.3"
  sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

  url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
  homepage "https://brew.sh/"

  app "Caffeine.app"

  # simple string is evaluated at compile-time
  caveats <<~EOS
    Here are some things you might want to know.
  EOS
  # do block is evaluated at install-time
  caveats do
    "Cask token: #{token}"
  end
  # a do block may print and use a DSL
  caveats do
    puts "Custom text via puts followed by DSL-generated text:"
    path_environment_variable("/custom/path/bin")
  end
end
