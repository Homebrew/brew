cask "factor" do
  version "0.99"
  sha256 "8a7968b873b5e87c83b5d0f5ddb4d3d76a2460f5e5c14edac6b18fe5957bd7d6"

  url "https://downloads.factorcode.org/releases/#{version}/factor-macosx-x86-64-#{version}.dmg"
  name "Factor"
  desc "Programming language"
  homepage "https://factorcode.org/"

  livecheck do
    url "https://downloads.factorcode.org/releases/"
    regex(%r{href=.*?(\d+(?:\.\d+)+)/}i)
  end

  suite "factor"

  caveats do
    path_environment_variable "#{appdir}/factor"
  end
end
