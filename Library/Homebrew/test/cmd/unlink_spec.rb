# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/unlink"

RSpec.describe Homebrew::Cmd::UnlinkCmd do
  it_behaves_like "parseable arguments"

  it "unlinks a given Cask's symlinked artifacts", :cask do
    cask = Cask::CaskLoader.load(cask_path("with-binary"))
    InstallHelper.install_without_artifacts_with_caskfile(cask)
    binary = cask.config.binarydir/"binary"
    binary.dirname.mkpath
    binary.make_symlink(cask.staged_path/"binary")
    cmd = described_class.new(["--cask", "with-binary"])
    allow(cmd.args.named).to receive(:to_kegs_to_casks).and_return([[], [cask]])

    expect { cmd.run }.to output(/Unlinking Binary/).to_stdout
    expect(binary).not_to be_a_symlink
  end

  it "leaves symlinks the Cask no longer owns alone", :cask do
    cask = Cask::CaskLoader.load(cask_path("with-binary"))
    InstallHelper.install_without_artifacts_with_caskfile(cask)
    binary = cask.config.binarydir/"binary"
    binary.dirname.mkpath
    binary.make_symlink(cask.staged_path/"other")
    cmd = described_class.new(["--cask", "with-binary"])
    allow(cmd.args.named).to receive(:to_kegs_to_casks).and_return([[], [cask]])

    expect { cmd.run }.not_to output.to_stdout
    expect(binary).to be_a_symlink
  end

  it "unlinks a Formula", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }
    formula_prefix = Formula["testball"].prefix
    (formula_prefix/"bin").mkpath
    (formula_prefix/"bin/test").write "test"
    (HOMEBREW_PREFIX/"bin").mkpath
    (HOMEBREW_PREFIX/"bin/test").make_relative_symlink(formula_prefix/"bin/test")
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/"testball").make_relative_symlink(formula_prefix)

    expect { brew "unlink", "testball" }
      .to output(/Unlinking /).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
