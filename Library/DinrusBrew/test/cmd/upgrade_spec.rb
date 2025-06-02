# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"

RSpec.describe DinrusBrew::Cmd::UpgradeCmd do
  it_behaves_like "parseable arguments"

  it "upgrades a Formula and cleans up old versions", :integration_test do
    setup_test_formula "testball"
    (DINRUSBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(DINRUSBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(DINRUSBREW_CELLAR/"testball/0.0.1").not_to exist
  end
end
