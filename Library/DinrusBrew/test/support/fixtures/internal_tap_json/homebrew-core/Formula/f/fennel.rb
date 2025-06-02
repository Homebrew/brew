class Fennel < Formula
  desc "Lua Lisp Language"
  homepage "https://fennel-lang.org"
  url "https://github.com/bakpakin/Fennel/archive/refs/tags/1.4.0.tar.gz"
  sha256 "161eb7f17f86e95de09070214d042fb25372f71ad266f451431f3109e87965c7"
  license "MIT"

  bottle do
    sha256 cellar: :any_skip_relocation, all: "f46028597883cbc38864c61bd3fa402da9cb90ce97415d51a7b5279bc17f7bd0"
  end

  depends_on "lua"

  def install
    system "make"
    bin.install "fennel"

    lua = Formula["lua"]
    (share/"lua"/lua.version.major_minor).install "fennel.lua"
  end

  test do
    assert_match "hello, world!", shell_output("#{bin}/fennel -e '(print \"hello, world!\")'")
  end
end
