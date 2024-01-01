# frozen_string_literal: true

describe MacOS, :cask do
  it "says '/' is undeletable" do
    expect(described_class).to be_undeletable(
      "/",
    )
    expect(described_class).to be_undeletable(
      "/.",
    )
    expect(described_class).to be_undeletable(
      "/usr/local/Library/Taps/../../../..",
    )
  end

  it "says '/Applications' is undeletable" do
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
  end

  it "says the home directory is undeletable" do
    expect(described_class).to be_undeletable(
      Dir.home,
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/",
    )
    expect(described_class).to be_undeletable(
      "#{Dir.home}/Documents/..",
    )
  end

  it "says the user library directory is undeletable" do
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
  end

  it "says '/Applications/.app' is deletable" do
    expect(described_class).not_to be_undeletable(
      "/Applications/.app",
    )
  end

  it "says '/Applications/SnakeOil Professional.app' is deletable" do
    expect(described_class).not_to be_undeletable(
      "/Applications/SnakeOil Professional.app",
    )
  end
end
