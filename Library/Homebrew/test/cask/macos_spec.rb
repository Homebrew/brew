# typed: strict
# frozen_string_literal: true

RSpec.describe MacOS, :cask do
  test_each([
    "/",
    "/.",
    "/usr/local/Library/Taps/../../../..",
    "/Applications",
    "/Applications/",
    "/Applications/.",
    "/Applications/Mail.app/..",
    "~",
    "~/",
    "~/Documents/..",
    "~/Library",
    "~/Library/",
    "~/Library/.",
    "~/Library/Preferences/..",
    "~/Library/Keychains/login.keychain-db",
  ]) do |path|
    it "protects #{path}" do
      expect(described_class).to be_undeletable(path.sub(/\A~/, Dir.home))
    end
  end

  test_each([
    "/Applications/.app",
    "/Applications/SnakeOil Professional.app",
    "~/Library/Keychains2/login.keychain-db",
  ]) do |path|
    it "allows deletion of #{path}" do
      expect(described_class).not_to be_undeletable(path.sub(/\A~/, Dir.home))
    end
  end

  it "resolves symlinked parent directories" do
    link = mktmpdir/"link"
    link.make_symlink("/")
    expect(described_class).to be_undeletable(link/"Applications")
  end
end
