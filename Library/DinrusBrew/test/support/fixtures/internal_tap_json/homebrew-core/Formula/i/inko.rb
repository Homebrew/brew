class Inko < Formula
  desc "Safe and concurrent object-oriented programming language"
  homepage "https://inko-lang.org/"
  url "https://releases.inko-lang.org/0.14.0.tar.gz"
  sha256 "4e2c82911d6026f76c42ccc164dc45b1b5e331db2e9557460d9319d682668e65"
  license "MPL-2.0"
  head "https://github.com/inko-lang/inko.git", branch: "main"

  bottle do
    sha256 cellar: :any,                 arm64_sonoma:   "f6ff66fdfb3aac69263c32a8a29d13e9d28a80ae33807f34460e55d8c1b228c6"
    sha256 cellar: :any,                 arm64_ventura:  "be59d916d29d85bb8bc4474eb1c7d42a56236835c3c21b0e36fb9e9df0a25e6e"
    sha256 cellar: :any,                 arm64_monterey: "9522c1f89b997dedaa3167ce4dbfa4a2d8c660acddecd32a99a515922e851b52"
    sha256 cellar: :any,                 sonoma:         "8e32d823ce9712ae2d5a2b9cbe0c9b727223098b3e66b003da087032be9f6818"
    sha256 cellar: :any,                 ventura:        "178865db1e2b60b4085a2465e8a3879794030a6d22c99b58c95e4bdf5418ef1b"
    sha256 cellar: :any,                 monterey:       "6ef924939c42d7bb2ec4e0d65cf293147a593f829619928d2580b419ec19b26c"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "14a02c119990d6a17062290439ac74e6667b41dcb90b18cd90b36d2a09715e10"
  end

  depends_on "coreutils" => :build
  depends_on "rust" => :build
  depends_on "llvm@15"
  depends_on "zstd"

  uses_from_macos "libffi", since: :catalina
  uses_from_macos "ruby", since: :sierra

  def install
    ENV.prepend_path "PATH", Formula["coreutils"].opt_libexec/"gnubin"
    system "make", "build", "PREFIX=#{prefix}"
    system "make", "install", "PREFIX=#{prefix}"
  end

  test do
    (testpath/"hello.inko").write <<~EOS
      import std.stdio.STDOUT

      class async Main {
        fn async main {
          STDOUT.new.print('Hello, world!')
        }
      }
    EOS
    assert_equal "Hello, world!\n", shell_output("#{bin}/inko run hello.inko")
  end
end
