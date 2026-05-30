# typed: true
# frozen_string_literal: true

RSpec.describe MacOS, :cask do
  let(:klass) { MacOS }

  specify do
    expect(klass).to be_undeletable(
      "/",
    )
    expect(klass).to be_undeletable(
      "/.",
    )
    expect(klass).to be_undeletable(
      "/usr/local/Library/Taps/../../../..",
    )
    expect(klass).to be_undeletable(
      "/Applications",
    )
    expect(klass).to be_undeletable(
      "/Applications/",
    )
    expect(klass).to be_undeletable(
      "/Applications/.",
    )
    expect(klass).to be_undeletable(
      "/Applications/Mail.app/..",
    )
    expect(klass).to be_undeletable(
      Dir.home,
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/",
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/Documents/..",
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/Library",
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/Library/",
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/Library/.",
    )
    expect(klass).to be_undeletable(
      "#{Dir.home}/Library/Preferences/..",
    )
    expect(klass).not_to be_undeletable(
      "/Applications/.app",
    )
    expect(klass).not_to be_undeletable(
      "/Applications/SnakeOil Professional.app",
    )
  end
end
