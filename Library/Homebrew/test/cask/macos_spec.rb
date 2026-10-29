# typed: strict
# frozen_string_literal: true

RSpec.describe MacOS, :cask do
  specify do
    expect(described_class).to be_undeletable(
      "/",
    )
    expect(described_class).to be_undeletable(
      "/.",
    )
    expect(described_class).to be_undeletable(
      "/usr/local/Library/Taps/../../../..",
    )
    expect(described_class).to be_undeletable(
      "/Applications",
    )
    expect(described_class).to be_undeletable(
      "/Applications/",
    )
    expect(described_class).to be_undeletable(
      "/Applications/.",
    )
    expect(described_class).to be_undeletable(
      "/Applications/Mail.app/..",
    )
    expect(described_class).to be_undeletable(
      Dir.home,
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Documents/..",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Library",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Library/",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Library/.",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Library/Preferences/..",
    )
    expect(described_class).not_to be_undeletable(
      "/Applications/.app",
    )
    expect(described_class).not_to be_undeletable(
      "/Applications/SnakeOil Professional.app",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Library/Keychains/login.keychain-db",
    )
    expect(described_class).not_to be_undeletable(
      "#{Dir.home}/Library/Keychains2/login.keychain-db",
    )
  end

  it "resolves symlinked parent directories" do
    link = mktmpdir/"link"
    link.make_symlink("/")
    expect(described_class).to be_undeletable(link/"Applications")
  end
end
