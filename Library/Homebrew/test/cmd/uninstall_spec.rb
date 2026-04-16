# typed: false
# frozen_string_literal: true

require "cmd/uninstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::UninstallCmd do
  it_behaves_like "parseable arguments"

  it "uninstalls a given Formula", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect(HOMEBREW_CELLAR/"testball").to exist
    expect { brew "uninstall", "--force", "testball" }
      .to output(/Uninstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_CELLAR/"testball").not_to exist
  end

  it "catches cask uninstall errors and sets Homebrew.failed" do
    allow(Cask::Uninstall).to receive(:uninstall_casks).and_raise(Cask::CaskError.new("test cask error"))
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Homebrew::Cleanup).to receive(:autoremove)

    cask = Cask::Cask.new("test-cask")
    cmd = described_class.new(["test-cask"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])

    expect { cmd.run }
      .to output(/test cask error/).to_stderr

    expect(Homebrew).to have_failed
  end
end
