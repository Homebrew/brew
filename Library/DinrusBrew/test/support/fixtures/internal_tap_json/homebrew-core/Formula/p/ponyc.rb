class Ponyc < Formula
  desc "Object-oriented, actor-model, capabilities-secure programming language"
  homepage "https://www.ponylang.io/"
  url "https://github.com/ponylang/ponyc.git",
      tag:      "0.58.1",
      revision: "fe3895eb4af494bf36d7690641bdfb5755db8350"
  license "BSD-2-Clause"

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_sonoma:   "e3aecfcf02aea56d53d82691e2ad7a780f771023d7070271bfce96b17439a34d"
    sha256 cellar: :any_skip_relocation, arm64_ventura:  "6ff83717191e16e4f852fb3be8f838afba312cc39e601bb5cebd2a618a328658"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "25c91bce200583a96f4cea34f31393c8f10eadcab363cc7d4d864d15f5f97e25"
    sha256 cellar: :any_skip_relocation, sonoma:         "5f4c550ce33e2970e0ada18a409755fa62936181289a21c15582ff80343866b6"
    sha256 cellar: :any_skip_relocation, ventura:        "f26c799f45013685da779bf2008ebe1907f9b3a93d5f260ce271a3f3b628da50"
    sha256 cellar: :any_skip_relocation, monterey:       "1cff10d068b36b18b253d235424c4f5aef71ff9ee44f2522c4b041dd4383ec30"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "ab49318d75eed3ee932c8e5add22f252ec0c852aad94945022877f926e93899f"
  end

  depends_on "cmake" => :build
  depends_on "python@3.12" => :build

  uses_from_macos "llvm" => [:build, :test]
  uses_from_macos "zlib"

  # We use LLVM to work around an error while building bundled `google-benchmark` with GCC
  fails_with :gcc do
    cause <<-EOS
      .../src/gbenchmark/src/thread_manager.h:50:31: error: expected ')' before '(' token
         50 |   GUARDED_BY(GetBenchmarkMutex()) Result results;
            |                               ^
    EOS
  end

  def install
    inreplace "CMakeLists.txt", "PONY_COMPILER=\"${CMAKE_C_COMPILER}\"", "PONY_COMPILER=\"#{ENV.cc}\"" if OS.linux?

    ENV["CMAKE_FLAGS"] = "-DCMAKE_OSX_SYSROOT=#{MacOS.sdk_path}" if OS.mac?
    ENV["MAKEFLAGS"] = "build_flags=-j#{ENV.make_jobs}"

    system "make", "libs"
    system "make", "configure"
    system "make", "build"
    system "make", "install", "DESTDIR=#{prefix}"
  end

  test do
    # ENV["CC"] returns llvm_clang, which does not work in a test block.
    ENV.clang

    system "#{bin}/ponyc", "-rexpr", "#{prefix}/packages/stdlib"

    (testpath/"test/main.pony").write <<~EOS
      actor Main
        new create(env: Env) =>
          env.out.print("Hello World!")
    EOS
    system "#{bin}/ponyc", "test"
    assert_equal "Hello World!", shell_output("./test1").strip
  end
end
