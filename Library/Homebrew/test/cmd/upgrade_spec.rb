# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"
require "extend/os/pkgconf"

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

  it "links newer version when upgrade was interrupted", :integration_test do
    setup_test_formula "testball"

    (HOMEBREW_CELLAR/"testball/0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(HOMEBREW_CELLAR/"testball/0.1").to be_a_directory
    expect(HOMEBREW_PREFIX/"opt/testball").to be_a_symlink
    expect(HOMEBREW_PREFIX/"var/homebrew/linked/testball").to be_a_symlink
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

  it "refuses to upgrades a forbidden formula", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "upgrade", "testball", { "HOMEBREW_FORBIDDEN_FORMULAE" => "testball" } }
      .to not_to_output(%r{#{HOMEBREW_CELLAR}/testball/0\.1}o).to_stdout
      .and output(/testball was forbidden/).to_stderr
      .and be_a_failure
    expect(HOMEBREW_CELLAR/"testball/0.1").not_to exist
  end

  context "when pkgconf needs reinstall due to SDK mismatch" do
    before do
      allow(OS).to receive(:mac?).and_return(true)
      allow(Homebrew::Pkgconf).to receive(:macos_sdk_mismatch)
        .and_return({ built_on_version: "13", current_version: "14" })
    end

    it "calls reinstall_pkgconf_if_needed! without crashing" do
      expect(Homebrew::Reinstall)
        .to receive(:reinstall_pkgconf_if_needed!)
        .with(dry_run: false)

      expect { brew "upgrade" }.to be_a_success
    end
  end

  context "when pkgconf has no mismatch" do
    before do
      allow(OS).to receive(:mac?).and_return(true)
      allow(Homebrew::Pkgconf).to receive(:macos_sdk_mismatch).and_return(nil)
    end

    it "does not call reinstall_pkgconf_if_needed!" do
      expect(Homebrew::Reinstall).not_to receive(:reinstall_pkgconf_if_needed!)

      expect { brew "upgrade" }.to be_a_success
    end
  end
end
