cask "smlnj" do
  version "110.99.4"
  sha256 "2bf858017b8ba43a70b30527290ed9fbbc81d9eaac1abeba62469d95392019a3"

  url "http://smlnj.cs.uchicago.edu/dist/working/#{version}/smlnj-amd64-#{version}.pkg",
      verified: "smlnj.cs.uchicago.edu/"
  name "Standard ML of New Jersey"
  desc "Compiler for the Standard ML '97 programming language"
  homepage "https://www.smlnj.org/"

  livecheck do
    url :homepage
    regex(%r{href=.*?/smlnj-amd64-(\d+(?:\.\d+)*)\.pkg}i)
  end

  pkg "smlnj-amd64-#{version}.pkg"

  uninstall pkgutil: "org.smlnj.amd64.pkg"

  zap delete: "/usr/local/smlnj"

  caveats do
    path_environment_variable "/usr/local/smlnj/bin"
  end
end
