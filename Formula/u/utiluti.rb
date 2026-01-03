class Utiluti < Formula
  desc "macOS command-line to work with default apps"
  homepage "https://github.com/scriptingosx/utiluti"
  url "https://github.com/scriptingosx/utiluti/archive/refs/tags/v1.3.tar.gz"
  sha256 "98d72888421cf048d157da3b64dcc4bdc165c4899de987636a1cac022e5bd7ff"
  license "Apache-2.0"
  head "https://github.com/scriptingosx/utiluti.git", branch: "main"

  depends_on :macos
  uses_from_macos "swift"

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release"
    bin.install ".build/release/utiluti"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/utiluti --version")
  end
end
