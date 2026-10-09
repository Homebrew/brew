# typed: strict
# frozen_string_literal: true

require "version_change"

RSpec.describe VersionChange do
  it "deduplicates equal changes" do
    changes = [version_change("gh", "2.93.0", "2.95.0"), version_change("gh", "2.93.0", "2.95.0")]

    expect(changes.uniq.count).to eq(1)
  end

  it "distinguishes changes with different sizes" do
    expect(version_change("gh", "2.93.0", "2.95.0",
                          size: "13.4MB")).not_to eq(version_change("gh", "2.93.0", "2.95.0"))
  end
end
