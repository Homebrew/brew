# typed: false
# frozen_string_literal: true

require "cmd/outdated"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Outdated do
  it_behaves_like "parseable arguments"

  it "skips auto-updating casks without --greedy-auto-updates", :cask do
    cask = Cask::CaskLoader.load(cask_path("auto-updates"))
    cmd = described_class.new([])

    expect(cask).not_to receive(:outdated?)
    expect(cmd.send(:select_outdated, [cask])).to be_empty
  end

  it "checks auto-updating casks with --greedy-auto-updates", :cask do
    cask = Cask::CaskLoader.load(cask_path("auto-updates"))
    cmd = described_class.new(["--greedy-auto-updates"])

    expect(cask).to receive(:outdated?)
      .with(greedy: false, greedy_latest: false, greedy_auto_updates: true)
      .and_return(true)
    expect(cmd.send(:select_outdated, [cask])).to eq([cask])
  end

  it "outputs JSON", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expected_json = JSON.pretty_generate({
      formulae: [{
        name:               "testball",
        installed_versions: ["0.0.1"],
        current_version:    "0.1",
        pinned:             false,
        pinned_version:     nil,
      }],
      casks:    [],
    })

    expect { brew "outdated", "--json=v2" }
      .to output("#{expected_json}\n").to_stdout
      .and be_a_success
  end
end
