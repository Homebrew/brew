# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"

RSpec.describe Homebrew::Cmd::UpgradeCmd do
  include FileUtils
  it_behaves_like "parseable arguments"

  it "upgrades a Formula and cleans up old versions", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
  end

  it "upgrades with asking for user prompts", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect do
      brew "upgrade", "--ask"
    end.to output(/.*Formula\s*\(1\):\s*testball.*/).to_stdout.and not_to_output.to_stderr

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_CELLAR/"testball/0.0.1").not_to exist
  end
end
