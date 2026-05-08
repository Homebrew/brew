# typed: false
# frozen_string_literal: true

require "os"

RSpec.describe OS do
  it "detects nix-homebrew from its repository" do
    stub_const("HOMEBREW_REPOSITORY", HOMEBREW_PREFIX/"Library/.homebrew-is-managed-by-nix")

    expect(described_class.nix_managed_homebrew?).to be(true)
    expect(described_class.nix_managed_homebrew_issues_url)
      .to eq("https://github.com/zhaofengli/nix-homebrew/issues")
  end

  it "detects nix-homebrew from its prefix marker" do
    mktmpdir do |prefix|
      stub_const("HOMEBREW_PREFIX", prefix)
      stub_const("HOMEBREW_REPOSITORY", prefix/"Library/Homebrew")

      (prefix/".managed_by_nix_darwin").write("")

      expect(described_class.nix_managed_homebrew?).to be(true)
    end
  end

  it "detects nix-homebrew from update environment values" do
    old_update_before = ENV.fetch("HOMEBREW_UPDATE_BEFORE", nil)
    old_update_after = ENV.fetch("HOMEBREW_UPDATE_AFTER", nil)
    mktmpdir do |prefix|
      stub_const("HOMEBREW_PREFIX", prefix)
      stub_const("HOMEBREW_REPOSITORY", prefix/"Library/Homebrew")
      ENV["HOMEBREW_UPDATE_BEFORE"] = "nix"
      ENV["HOMEBREW_UPDATE_AFTER"] = "nix"

      expect(described_class.nix_managed_homebrew?).to be(true)
    end
  ensure
    ENV["HOMEBREW_UPDATE_BEFORE"] = old_update_before
    ENV["HOMEBREW_UPDATE_AFTER"] = old_update_after
  end

  it "detects nix-darwin from a Nix store Brewfile" do
    mktmpdir do |prefix|
      stub_const("HOMEBREW_PREFIX", prefix)
      stub_const("HOMEBREW_REPOSITORY", prefix/"Library/Homebrew")
      stub_const("ARGV", ["bundle", "--file=/nix/store/example-Brewfile"])

      expect(described_class.nix_managed_homebrew?).to be(true)
      expect(described_class.nix_managed_homebrew_issues_url)
        .to eq("https://github.com/nix-darwin/nix-darwin/issues")
    end
  end
end
