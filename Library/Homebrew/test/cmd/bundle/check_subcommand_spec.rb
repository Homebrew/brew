# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/check"
require "bundle/dsl"
require "bundle/skipper"

RSpec.describe Homebrew::Cmd::Bundle::CheckSubcommand, :no_api do
  let(:do_check) do
    described_class.new(args_for_subcommand(:check), context:).run
  end
  let(:context) { bundle_subcommand_context(:check, no_upgrade:, verbose:) }
  let(:no_upgrade) { false }
  let(:verbose) { false }

  before do
    Homebrew::Bundle::Checker.reset!
    allow_any_instance_of(IO).to receive(:puts)
    stub_formula_loader formula("mas") {
      T.bind(self, T.class_of(Formula))
      url "mas-1.0"
    }
  end

  context "when dependencies are satisfied" do
    it "does not raise an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      nothing = []
      allow(Homebrew::Bundle::Checker).to receive_messages(casks_to_install:    nothing,
                                                           formulae_to_install: nothing,
                                                           apps_to_install:     nothing,
                                                           taps_to_tap:         nothing)
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
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("cask 'abc'")
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when formulae are not installed" do
    let(:verbose) { true }

    it "raises an error and outputs to stderr" do
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      expect { do_check }.to raise_error(SystemExit).and \
        output(/brew bundle can't satisfy your Brewfile's dependencies/).to_stderr.and \
          not_to_output(/brew bundle can't satisfy your Brewfile's dependencies/).to_stdout
    end

    it "partially outputs when HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS is set" do
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      ENV["HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS"] = "abc"
      expect { do_check }.to raise_error(SystemExit).and \
        output("Satisfy missing dependencies with `brew bundle install`.\n").to_stderr
    end

    it "does not raise error on skippable formula" do
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(true)
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      expect { do_check }.not_to raise_error
    end
  end

  context "when formulae have the wrong link status" do
    before do
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive_messages(upgradable_formulae: [], installed_formulae: ["abc"])
      stub_formula_loader formula("abc") {
        T.bind(self, T.class_of(Formula))
        url "abc-1.0"
      }
    end

    it "raises an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc', link: true")
      allow(Formula["abc"]).to receive_messages(linked?: false, keg_only?: false)

      expect { do_check }.to raise_error(SystemExit).and \
        output(/Run `brew bundle check --verbose` to list unmet dependencies\./).to_stderr
    end

    it "raises an error for an implicitly unlinked non-keg-only formula" do
      Homebrew::Bundle::Brew.instance_variable_set(:@formulae_by_name, { "abc" => { link?: false } })
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      allow(Formula["abc"]).to receive(:linked?).and_return(false)

      expect { do_check }.to raise_error(SystemExit).and \
        output(/Run `brew bundle check --verbose` to list unmet dependencies\./).to_stderr
    end

    it "does not raise an error when live link status satisfies an implicit check" do
      Homebrew::Bundle::Brew.instance_variable_set(:@formulae_by_name, { "abc" => { link?: false } })
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      allow(Formula["abc"]).to receive(:linked?).and_return(true)

      expect { do_check }.not_to raise_error
    end

    context "with verbose mode enabled" do
      let(:verbose) { true }

      it "outputs the link status error" do
        allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc', link: false")
        allow(Formula["abc"]).to receive_messages(linked?: true, keg_only?: false)

        expect { do_check }.to raise_error(SystemExit).and \
          output(/Formula abc needs to be unlinked\./).to_stderr
      end

      it "outputs the implicit link status error" do
        Homebrew::Bundle::Brew.instance_variable_set(:@formulae_by_name, { "abc" => { link?: true } })
        allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
        allow(Formula["abc"]).to receive(:linked?).and_return(true)

        expect { do_check }.to raise_error(SystemExit).and \
          output(/Formula abc needs to be unlinked\./).to_stderr
      end
    end

    context "with install mode enabled" do
      it "raises an error after install leaves a formula with the wrong link status" do
        args = args_for_subcommand(:check, install?: true, global?: false, verbose?: false, upgrade_formulae: nil,
                                           jobs: nil, file: nil)
        allow(Homebrew::Cmd::Bundle).to receive(:redirect_stdout).and_yield
        allow(Homebrew::Bundle::Brew).to receive(:install!).and_return(true)
        allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc', link: true")
        allow(Formula["abc"]).to receive_messages(linked?: false, keg_only?: false)

        expect { Homebrew::Cmd::Bundle.dispatch(args, extensions: Homebrew::Bundle.extensions) }
          .to raise_error(SystemExit).and \
            output(/Run `brew bundle check --verbose` to list unmet dependencies\./).to_stderr
      end
    end
  end

  context "when taps are not tapped" do
    it "raises an error" do
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("tap 'abc/def'")
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when apps are not installed", :needs_macos do
    it "raises an error" do
      allow(Homebrew::Bundle::MacAppStore).to receive(:app_ids).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
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
      allow_any_instance_of(Homebrew::Bundle::MacAppStore).to \
        receive(:installed_and_up_to_date?).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive_messages(installed_formulae:  ["abc", "def"],
                                                        upgradable_formulae: [])
      allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with("abc").and_return(true)
      allow(Homebrew::Bundle::Brew::Services).to receive(:started?).with("def").and_return(false)
    end

    it "does not raise error when no service needs to be started" do
      Homebrew::Bundle::Checker.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")

      expect(Homebrew::Bundle::Brew.installed_formulae).to include("abc")
      expect(Homebrew::Bundle::Cask.installed_casks).not_to include("abc")
      expect(Homebrew::Bundle::Brew::Services.started?("abc")).to be(true)

      expect { do_check }.not_to raise_error
    end

    context "when restart_service is true" do
      it "raises an error" do
        allow_any_instance_of(Pathname)
          .to receive(:read).and_return("brew 'abc', restart_service: true\nbrew 'def', restart_service: true")
        allow_any_instance_of(Homebrew::Bundle::MacAppStore)
          .to receive(:format_checkable).and_return(1 => "foo")
        expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stderr
      end
    end

    context "when start_service is true" do
      it "raises an error" do
        allow_any_instance_of(Pathname)
          .to receive(:read).and_return("brew 'abc', start_service: true\nbrew 'def', start_service: true")
        allow_any_instance_of(Homebrew::Bundle::MacAppStore)
          .to receive(:format_checkable).and_return(1 => "foo")
        expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stderr
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
      allow_any_instance_of(Homebrew::Bundle::MacAppStore).to \
        receive(:installed_and_up_to_date?).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:installed_formulae).and_return(["abc", "def"])
    end

    it "raises an error that doesn't mention upgrade" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'")
      allow_any_instance_of(Homebrew::Bundle::MacAppStore).to \
        receive(:format_checkable).and_return(1 => "foo")
      expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stderr
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
      allow_any_instance_of(Homebrew::Bundle::VscodeExtension).to \
        receive(:installed_and_up_to_date?).and_return(false)
    end

    it "raises an error that doesn't mention upgrade" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("vscode 'foo'")
      expect { do_check }.to raise_error(SystemExit).and output(expected_output).to_stderr
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
      allow(Homebrew::Bundle::Checker).to receive(:registered_extensions_to_install).and_return(["asdf"])
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
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:upgradable_formulae).and_return([])
      allow_any_instance_of(Pathname).to receive(:read).and_return("brew 'abc'\nbrew 'def'")

      expect_any_instance_of(Homebrew::Bundle::Brew).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first missing cask", :needs_macos do
      allow_any_instance_of(Pathname).to receive(:read).and_return("cask 'abc'\ncask 'def'")

      expect_any_instance_of(Homebrew::Bundle::Cask).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first missing mac app", :needs_macos do
      allow_any_instance_of(Pathname).to receive(:read).and_return("mas 'foo', id: 123\nmas 'bar', id: 456")

      expect_any_instance_of(Homebrew::Bundle::MacAppStore).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end

    it "stops checking after the first VSCode extension" do
      allow_any_instance_of(Pathname).to receive(:read).and_return("vscode 'abc'\nvscode 'def'")

      expect_any_instance_of(Homebrew::Bundle::VscodeExtension).to \
        receive(:exit_early_check).once.and_call_original
      expect { do_check }.to raise_error(SystemExit)
    end
  end

  context "when a new checker fails to implement installed_and_up_to_date" do
    it "raises an exception" do
      stub_const("TestChecker", Class.new(Homebrew::Bundle::PackageType) do
        def self.type = :test
        def self.check_label = "Test"

        def self.reset!; end

        def self.preinstall!(name, no_upgrade: false, verbose: false, **options)
          _ = name
          _ = no_upgrade
          _ = verbose
          _ = options
        end

        def self.install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
          _ = name
          _ = preinstall
          _ = no_upgrade
          _ = verbose
          _ = force
          _ = options
        end

        def self.dump
          ""
        end
      end.freeze)

      test_entry = Homebrew::Bundle::Dsl::Entry.new(:test, "test")
      expect { TestChecker.new.find_actionable([test_entry]) }.to raise_error(NotImplementedError)
    end
  end
end
