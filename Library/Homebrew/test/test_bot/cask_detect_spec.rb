# typed: strict
# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::CaskDetect do
  it "selects cask source files from the changed paths" do
    tap = Tap.fetch("example", "test")
    allow(Utils).to receive(:safe_popen_read).with(
      "git", "-C", tap.path, "diff-tree", "-r", "--name-only", "-z", "--diff-filter=AMR",
      "base", "head", "--", tap.cask_dir
    ).and_return("Casks/added.rb\0Casks/nested/modified.rb\0Casks/README.md\0")

    expect(described_class.new(tap:, git: "git").run!("base", "head"))
      .to eq(%w[Casks/added.rb Casks/nested/modified.rb])
  end
end
