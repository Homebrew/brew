# frozen_string_literal: true

require "bundle"
require "bundle/commands/check"
require "bundle/brew_checker"
require "bundle/cask_checker"
require "bundle/mac_app_store_checker"
require "bundle/vscode_extension_checker"
require "bundle/formula_installer"
require "bundle/cask_installer"
require "bundle/mac_app_store_installer"
require "bundle/dsl"
require "bundle/skipper"

RSpec.describe Homebrew::Bundle::Commands::Check, :no_api do
  let(:do_check) do
    described_class.run(no_upgrade:, verbose:)
  end
  let(:no_upgrade) { false }
  let(:verbose) { false }

  before do
    Homebrew::Bundle::Checker.reset!
    allow_any_instance_of(IO).to receive(:puts)
    stub_formula_loader formula("mas") { url "mas-1.0" }
  end

  context "when dependencies are satisfied" do
    it "does not raise an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      nothing = []
      allow(Homebrew::Bundle::Checker).to receive_messages(casks_to_install:      nothing,
                                                           formulae_to_install:   nothing,
                                                           apps_to_install:       nothing,
                                                           taps_to_tap:           nothing,
                                                           extensions_to_install: nothing)
      expect { do_check }.not_to raise_error
    end
  end

  context "when no dependencies are specified" do
    it "does not raise an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow_any_instance_of(Homebrew::Bundle::Dsl).to receive(:entries).and_return([])
      expect { do_check }.not_to raise_error
    end
  end

  context "when casks are not installed", :needs_macos do
    it "raises an error" do
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("cask 'abc'")
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when formulae are not installed" do
    let(:verbose) { true }

    it "raises an error and outputs to stdout" do
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      expect { do_check }.to raise_error(SystemExit).and \
        output(/brew bundle can't satisfy your Brewfile's dependencies/).to_stdout
    end

    it "partially outputs when HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS is set" do
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      ENV["HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS"] = "abc"
      expect { do_check }.to raise_error(SystemExit).and \
        output("Satisfy missing dependencies with `brew bundle install`.\n").to_stdout
    end

    it "does not raise error on skippable formula" do
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(true)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      expect { do_check }.not_to raise_error
    end
  end

  context "when taps are not tapped" do
    it "raises an error" do
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("tap 'abc/def'")
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when apps are not installed", :needs_macos do
    it "raises an error" do
      allow(Homebrew::Bundle::MacAppStoreDumper).to receive(:app_ids).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("mas 'foo', id: 123")
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when service is not started and app not installed" do
    let(:verbose) { true }
    let(:expected_output) do
      <<~MSG
        brew bundle can't satisfy your Brewfile's dependencies.
        → App foo needs to be installed or updated.
        → Service def needs to be started.
        Satisfy missing dependencies with `brew bundle install`.
      MSG
    end

    before do
      Homebrew::Bundle::Checker.reset!
      allow_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker).to \
        receive(:installed_and_up_to_date?).and_return(false)
      allow(Homebrew::Bundle::FormulaInstaller).to receive_messages(installed_formulae:  ["abc", "def"],
                                                                    upgradable_formulae: [])
      allow(Homebrew::Bundle::BrewServices).to receive(:started?).with("abc").and_return(true)
      allow(Homebrew::Bundle::BrewServices).to receive(:started?).with("def").and_return(false)
    end

    it "does not raise error when no service needs to be started" do
      Homebrew::Bundle::Checker.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")

      expect(Homebrew::Bundle::FormulaInstaller.installed_formulae).to include("abc")
      expect(Homebrew::Bundle::CaskInstaller.installed_casks).not_to include("abc")
      expect(Homebrew::Bundle::BrewServices.started?("abc")).to be(true)

      expect { do_check }.not_to raise_error
    end

    context "when restart_service is true" do
      it "raises an error" do
        allow_any_instance_of(Pathname)
          .to receive(:read).and_return("brew 'abc', restart_service: true\nbrew 'def', restart_service: true")
        allow_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker)
          .to receive(:format_checkable).and_return(1 => "foo")
        expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stdout
      end
    end

    context "when start_service is true" do
      it "raises an error" do
        allow_any_instance_of(Pathname)
          .to receive(:read).and_return("brew 'abc', start_service: true\nbrew 'def', start_service: true")
        allow_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker)
          .to receive(:format_checkable).and_return(1 => "foo")
        expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stdout
      end
    end
  end

  context "when app not installed and `no_upgrade` is true" do
    let(:expected_output) do
      <<~MSG
        brew bundle can't satisfy your Brewfile's dependencies.
        → App foo needs to be installed.
        Satisfy missing dependencies with `brew bundle install`.
      MSG
    end
    let(:no_upgrade) { true }
    let(:verbose) { true }

    before do
      Homebrew::Bundle::Checker.reset!
      allow_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker).to \
        receive(:installed_and_up_to_date?).and_return(false)
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:installed_formulae).and_return(["abc", "def"])
    end

    it "raises an error that doesn't mention upgrade" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      allow_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker).to \
        receive(:format_checkable).and_return(1 => "foo")
      expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stdout
    end
  end

  context "when extension not installed" do
    let(:expected_output) do
      <<~MSG
        brew bundle can't satisfy your Brewfile's dependencies.
        → VSCode Extension foo needs to be installed.
        Satisfy missing dependencies with `brew bundle install`.
      MSG
    end
    let(:verbose) { true }

    before do
      Homebrew::Bundle::Checker.reset!
      allow_any_instance_of(Homebrew::Bundle::Checker::VscodeExtensionChecker).to \
        receive(:installed_and_up_to_date?).and_return(false)
    end

    it "raises an error that doesn't mention upgrade" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("vscode 'foo'")
      expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stdout
    end
  end

  context "when there are taps to install" do
    before do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(Homebrew::Bundle::Checker).to receive(:taps_to_tap).and_return(["asdf"])
    end

    it "does not check for casks" do
      expect(Homebrew::Bundle::Checker).not_to receive(:casks_to_install)
      expect { do_check }.to raise_error(SystemExit)
    end

    it "does not check for formulae" do
      expect(Homebrew::Bundle::Checker).not_to receive(:formulae_to_install)
      expect { do_check }.to raise_error(SystemExit)
    end

    it "does not check for apps" do
      expect(Homebrew::Bundle::Checker).not_to receive(:apps_to_install)
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when there are VSCode extensions to install" do
    before do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(Homebrew::Bundle::Checker).to receive(:extensions_to_install).and_return(["asdf"])
    end

    it "does not check for formulae" do
      expect(Homebrew::Bundle::Checker).not_to receive(:formulae_to_install)
      expect { do_check }.to raise_error(SystemExit)
    end

    it "does not check for apps" do
      expect(Homebrew::Bundle::Checker).not_to receive(:apps_to_install)
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when there are formulae to install" do
    before do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(Homebrew::Bundle::Checker).to \
        receive_messages(taps_to_tap:         [],
                         casks_to_install:    [],
                         apps_to_install:     [],
                         formulae_to_install: ["one"])
    end

    it "does not start formulae" do
      expect(Homebrew::Bundle::Checker).not_to receive(:formulae_to_start)
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when verbose mode is not enabled" do
    it "stops checking after the first missing formula" do
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::FormulaInstaller).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'\nbrew 'def'")

      expect_any_instance_of(Homebrew::Bundle::Checker::BrewChecker).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first missing cask", :needs_macos do
      allow_any_instance_of(Pathname).to receive(:read).and_return("cask 'abc'\ncask 'def'")

      expect_any_instance_of(Homebrew::Bundle::Checker::CaskChecker).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first missing mac app", :needs_macos do
      allow_any_instance_of(Pathname).to receive(:read).and_return("mas 'foo', id: 123\nmas 'bar', id: 456")

      expect_any_instance_of(Homebrew::Bundle::Checker::MacAppStoreChecker).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first VSCode extension" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("vscode 'abc'\nvscode 'def'")

      expect_any_instance_of(Homebrew::Bundle::Checker::VscodeExtensionChecker).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when a new checker fails to implement installed_and_up_to_date" do
    it "raises an exception" do
      stub_const("TestChecker", Class.new(Homebrew::Bundle::Checker::Base) do
        class_eval("PACKAGE_TYPE = :test", __FILE__, __LINE__)
      end.freeze)

      test_entry = Homebrew::Bundle::Dsl::Entry.new(:test, "test")
      expect { TestChecker.new.find_actionable([test_entry]) }.to raise_error(NotImplementedError)
    end
  end
end
