# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe AbstractFileDownloadStrategy do
  subject(:strategy) { Class.new(described_class).new(url, "foo", "1.2.3") }

  let(:url) { "https://example.com/foo.tar.gz" }

  describe "#parse_basename" do
    it "returns the final path segment for simple URLs" do
      expect(strategy.parse_basename("https://example.com/foo.tar.gz")).to eq("foo.tar.gz")
    end

    it "prefers a path segment with an extension over later extensionless segments" do
      expect(strategy.parse_basename("https://example.com/foo-1.0.tar.gz/download")).to eq("foo-1.0.tar.gz")
    end

    it "extracts the basename from a response-content-disposition query parameter" do
      url = "https://example.com/download.php?file=ignored&response-content-disposition=attachment;filename=\"real.tar.gz\""
      expect(strategy.parse_basename(url)).to eq("real.tar.gz")
    end

    it "uses the query value when the path has no extension" do
      url = "https://example.com/download.php?file=foo-1.0.tar.gz"
      expect(strategy.parse_basename(url)).to eq("foo-1.0.tar.gz")
    end

    it "returns the final segment for file:// URLs even when an ancestor directory contains a dot" do
      expect(strategy.parse_basename("file:///Users/me/git-repos/github.com/Homebrew/brew/naked_executable"))
        .to eq("naked_executable")
    end

    it "returns the final segment for file:// URLs with an extension" do
      expect(strategy.parse_basename("file:///tmp/foo.tar.gz")).to eq("foo.tar.gz")
    end
  end
end
