# typed: false
# frozen_string_literal: true

require "cmd/tab"
require "cmd/shared_examples/args_parse"
require "tab"
require "cask"

RSpec.describe Homebrew::Cmd::TabCmd do
  def installed_on_request?(formula)
    # `brew` subprocesses can change the tab, invalidating the cached values.
    Tab.clear_cache
    Tab.for_formula(formula).installed_on_request
  end

  it_behaves_like "parseable arguments"

  it "marks or unmarks a formula as installed on request", :integration_test do
    setup_test_formula "foo",
                       tab_attributes: { "installed_on_request" => false }
    foo = Formula["foo"]

    expect { brew "tab", "--installed-on-request", "foo" }
      .to be_a_success
      .and output(/foo is now marked as installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(installed_on_request?(foo)).to be true

    expect { brew "tab", "--no-installed-on-request", "foo" }
      .to be_a_success
      .and output(/foo is now marked as not installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(installed_on_request?(foo)).to be false
  end

  context "with an installed cask" do
    let(:cask) { Cask::CaskLoader.load(cask_path("local-caffeine")) }
    let(:tabfile) { cask.metadata_main_container_path/AbstractTab::FILENAME }

    before do
      InstallHelper.install_with_caskfile(cask)
      Cask::Tab.clear_cache
    end

    # Casks installed as a dependency, or installed before cask Tab support
    # existed, can end up with no INSTALL_RECEIPT.json on disk. `brew tab`
    # should still be able to record the on-request flag for them instead of
    # erroring out (Homebrew/brew#22206).
    specify "marks the cask as installed on request and creates the Tab file when none exists", :cask do
      expect(cask).to be_installed
      expect(tabfile).not_to exist

      cmd = described_class.new(["--installed-on-request", "--cask", cask.token])
      expect { cmd.run }
        .to output(/local-caffeine is now marked as installed on request/).to_stdout
        .and output(/No install receipt for local-caffeine; creating one to record this flag\./).to_stderr

      expect(tabfile).to exist
      Cask::Tab.clear_cache
      tab = Cask::Tab.for_cask(cask)
      expect(tab.installed_on_request).to be true
      # Confirm `Cask::Tab.create` was used (vs `empty`) so the synthesized Tab
      # carries real metadata, not just the on-request flag.
      expect(tab.source["version"]).to eq(cask.version.to_s)
      expect(tab.uninstall_artifacts).not_to be_nil
    end

    specify "treats --no-installed-on-request as a no-op when no Tab file exists", :cask do
      expect(cask).to be_installed
      expect(tabfile).not_to exist

      cmd = described_class.new(["--no-installed-on-request", "--cask", cask.token])
      expect { cmd.run }
        .to output(/local-caffeine is already marked as not installed on request/).to_stdout
        .and not_to_output(/No install receipt/).to_stderr

      # The no-op path should not synthesize a Tab on disk.
      expect(tabfile).not_to exist
    end

    specify "marks an existing-tabfile cask as installed on request without resynthesizing", :cask do
      tab = Cask::Tab.create(cask)
      tab.installed_on_request = false
      # Stamp a sentinel that `Cask::Tab.create` would clobber if it ran again,
      # so the assertion below catches any resynth regression even within the
      # same wall-clock second (`Time.now.to_i` would otherwise be same-second).
      tab.homebrew_version = "0.0.0-existing-tabfile-sentinel"
      tab.write
      Cask::Tab.clear_cache
      expect(tabfile).to exist

      cmd = described_class.new(["--installed-on-request", "--cask", cask.token])
      expect { cmd.run }
        .to output(/local-caffeine is now marked as installed on request/).to_stdout
        .and not_to_output(/No install receipt/).to_stderr

      Cask::Tab.clear_cache
      reloaded = Cask::Tab.for_cask(cask)
      expect(reloaded.installed_on_request).to be true
      # The sentinel is preserved, proving the existing Tab was updated rather
      # than replaced via `Cask::Tab.create` (which always overwrites
      # `homebrew_version` to `HOMEBREW_VERSION`).
      expect(reloaded.homebrew_version).to eq("0.0.0-existing-tabfile-sentinel")
    end
  end
end
