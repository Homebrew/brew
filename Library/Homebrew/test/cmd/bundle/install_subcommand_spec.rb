# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/install"
require "bundle/skipper"

RSpec.describe Homebrew::Cmd::Bundle::InstallSubcommand do
  subject(:install_subcommand) do
    described_class.new(
      args_for_subcommand(:install, quiet?: false, global?: global, cleanup?: false, force_cleanup?: false),
      context: bundle_subcommand_context(:install, global:),
    )
  end

  let(:global) { false }

  before do
    allow_any_instance_of(IO).to receive(:puts)
  end

  context "when a Brewfile is not found" do
    it "raises an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_raise(Errno::ENOENT)
      expect { install_subcommand.run }.to raise_error(RuntimeError)
    end
  end

  context "when a Brewfile is found", :no_api do
    before do
      Homebrew::Bundle::Cask.reset!
      allow(Homebrew::Bundle).to receive(:brew).and_return(true)
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?).and_return(false)
      allow(Homebrew::Bundle::Cask).to receive(:installable_or_upgradable?).and_return(true)
      allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return([])
    end

    let(:brewfile_contents) do
      <<~EOS
        tap 'phinze/cask'
        brew 'mysql', conflicts_with: ['mysql56']
        cask 'phinze/cask/google-chrome', greedy: true
        mas '1Password', id: 443987910
        vscode 'GitHub.codespaces'
        flatpak 'org.gnome.Calculator'
      EOS
    end

    it "does not raise an error" do
      allow(Homebrew::Bundle::Tap).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::VscodeExtension).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Flatpak).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::Cask).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::MacAppStore).to receive_messages(preinstall!: true, install!: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)
      expect { install_subcommand.run }.not_to raise_error
    end

    it "#dsl returns a valid DSL" do
      allow(Homebrew::Bundle::Tap).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::VscodeExtension).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Flatpak).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::Cask).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::MacAppStore).to receive_messages(preinstall!: true, install!: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)
      install_subcommand.run
      expect(install_subcommand.dsl.entries.first.name).to eql("phinze/cask")
    end

    it "does not raise an error when skippable" do
      expect(Homebrew::Bundle::Brew).not_to receive(:install!)

      allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(true)
      allow_any_instance_of(Pathname).to receive(:read)
        .and_return("brew 'mysql'")
      expect { install_subcommand.run }.not_to raise_error
    end

    it "exits on failures" do
      allow(Homebrew::Bundle::Brew).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::Cask).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::MacAppStore).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::Tap).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::VscodeExtension).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::Flatpak).to receive_messages(preinstall!: true, install!: false)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect { install_subcommand.run }.to raise_error(SystemExit)
    end

    it "skips installs from failed taps" do
      allow(Homebrew::Bundle::Cask).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Tap).to receive_messages(preinstall!: true, install!: false)
      allow(Homebrew::Bundle::Brew).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::MacAppStore).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::VscodeExtension).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::Flatpak).to receive_messages(preinstall!: true, install!: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect { install_subcommand.run }.to raise_error(SystemExit)
    end

    it "marks Brewfile formulae as installed_on_request after installing" do
      allow(Homebrew::Bundle::Tap).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::VscodeExtension).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Flatpak).to receive(:preinstall!).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::Cask).to receive_messages(preinstall!: true, install!: true)
      allow(Homebrew::Bundle::MacAppStore).to receive_messages(preinstall!: true, install!: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'test_formula'")

      expect(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      install_subcommand.run
    end

    it "asks before cleaning up when ask mode is enabled" do
      args = args_for_subcommand(:install, quiet?: false, global?: false, cleanup?: true, force_cleanup?: false)
      context = bundle_subcommand_context(:install, ask: true)
      subcommand = described_class.new(args, context:)
      allow(Homebrew::Bundle::Installer).to receive(:install!).and_return(true)
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'test_formula'")

      expect(Homebrew::Cmd::Bundle::CleanupSubcommand).to receive(:cleanup).with(
        global: false, file: nil, zap: false, force: false, ask: true, dsl: anything,
      )

      subcommand.run
    end

    it "force cleans up when --force-cleanup is passed" do
      args = args_for_subcommand(:install, quiet?: false, global?: false, cleanup?: false, force_cleanup?: true)
      subcommand = described_class.new(args,
                                       context: bundle_subcommand_context(:install,
                                                                          ask: true))
      allow(Homebrew::Bundle::Installer).to receive(:install!).and_return(true)
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'test_formula'")

      expect(Homebrew::Cmd::Bundle::CleanupSubcommand).to receive(:cleanup).with(
        global: false, file: nil, zap: false, force: true, ask: true, dsl: anything,
      )

      subcommand.run
    end

    it "force cleans up when --force and --cleanup are passed" do
      args = args_for_subcommand(:install, quiet?: false, global?: false, cleanup?: true, force_cleanup?: false)
      subcommand = described_class.new(args,
                                       context: bundle_subcommand_context(:install,
                                                                          force: true))
      allow(Homebrew::Bundle::Installer).to receive(:install!).and_return(true)
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'test_formula'")

      expect(Homebrew::Cmd::Bundle::CleanupSubcommand).to receive(:cleanup).with(
        global: false, file: nil, zap: false, force: true, ask: false, dsl: anything,
      )

      subcommand.run
    end

    it "rejects --cleanup without force or ask" do
      args = args_for_subcommand(:install, quiet?: false, global?: false, cleanup?: true, force_cleanup?: false)
      expect { described_class.new(args, context: bundle_subcommand_context(:install)).run }
        .to raise_error(UsageError, /requires `--force`, `--force-cleanup` or `\$HOMEBREW_ASK`/)
    end

    it "rejects --zap without a cleanup flag" do
      args = args_for_subcommand(:install, quiet?: false, global?: false, cleanup?: false, force_cleanup?: false,
                                           zap?: true)
      expect { described_class.new(args, context: bundle_subcommand_context(:install)).run }
        .to raise_error(UsageError, /`--zap` cannot be passed without `--cleanup` or `--force-cleanup`/)
    end
  end
end
