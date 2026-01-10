# frozen_string_literal: true

require "bundle"
require "bundle/commands/cleanup"

RSpec.describe Homebrew::Bundle::Commands::Cleanup do
  describe "read Brewfile and current installation", :no_api do
    before do
      described_class.reset!

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      allow_any_instance_of(Pathname).to receive(:read).and_return <<~EOS
        tap 'x'
        tap 'y'
        cask '123'
        brew 'a'
        brew 'b'
        brew 'd2'
        brew 'homebrew/tap/f'
        brew 'homebrew/tap/g'
        brew 'homebrew/tap/h'
        brew 'homebrew/tap/i2'
        brew 'homebrew/tap/hasdependency'
        brew 'hasbuilddependency1'
        brew 'hasbuilddependency2'
        mas 'appstoreapp1', id: 1
        vscode 'VsCodeExtension1'
      EOS
      %w[a b d2 homebrew/tap/f homebrew/tap/g homebrew/tap/h homebrew/tap/i2
         homebrew/tap/hasdependency hasbuilddependency1 hasbuilddependency2].each do |full_name|
        tap_name, _, name = full_name.rpartition("/")
        tap = tap_name.present? ? Tap.fetch(tap_name) : nil
        f = formula(name, tap:) { url "#{name}-1.0" }
        stub_formula_loader f, full_name
      end
    end

    it "computes which casks to uninstall" do
      cask_123 = instance_double(Cask::Cask, to_s: "123", old_tokens: [])
      cask_456 = instance_double(Cask::Cask, to_s: "456", old_tokens: [])
      allow(Homebrew::Bundle::CaskDumper).to receive(:casks).and_return([cask_123, cask_456])
      expect(described_class.casks_to_uninstall).to eql(%w[456])
    end

    it "computes which formulae to uninstall" do
      dependencies_arrays_hash = { dependencies: [], build_dependencies: [] }
      formulae_hash = [
        { name: "a2", full_name: "a2", aliases: ["a"], dependencies: ["d"] },
        { name: "c", full_name: "c" },
        { name: "d", full_name: "homebrew/tap/d", aliases: ["d2"] },
        { name: "e", full_name: "homebrew/tap/e" },
        { name: "f", full_name: "homebrew/tap/f" },
        { name: "h", full_name: "other/tap/h" },
        { name: "i", full_name: "homebrew/tap/i", aliases: ["i2"] },
        { name: "hasdependency", full_name: "homebrew/tap/hasdependency", dependencies: ["isdependency"] },
        { name: "isdependency", full_name: "homebrew/tap/isdependency" },
        {
          name:                "hasbuilddependency1",
          full_name:           "hasbuilddependency1",
          poured_from_bottle?: true,
          build_dependencies:  ["builddependency1"],
        },
        {
          name:                "hasbuilddependency2",
          full_name:           "hasbuilddependency2",
          poured_from_bottle?: false,
          build_dependencies:  ["builddependency2"],
        },
        { name: "builddependency1", full_name: "builddependency1" },
        { name: "builddependency2", full_name: "builddependency2" },
        { name: "caskdependency", full_name: "homebrew/tap/caskdependency" },
      ].map { |formula| dependencies_arrays_hash.merge(formula) }
      allow(Homebrew::Bundle::FormulaDumper).to receive(:formulae).and_return(formulae_hash)

      formulae_hash.each do |hash_formula|
        name = hash_formula[:name]
        full_name = hash_formula[:full_name]
        tap_name = full_name.rpartition("/").first.presence || "homebrew/core"
        tap = Tap.fetch(tap_name)
        f = formula(name, tap:) { url "#{name}-1.0" }
        stub_formula_loader f, full_name
      end

      allow(Homebrew::Bundle::CaskDumper).to receive(:formula_dependencies).and_return(%w[caskdependency])
      expect(described_class.formulae_to_uninstall).to eql %w[
        c
        homebrew/tap/e
        other/tap/h
        builddependency1
      ]
    end

    it "computes which tap to untap" do
      allow(Homebrew::Bundle::TapDumper).to \
        receive(:tap_names).and_return(%w[z homebrew/core homebrew/tap])
      expect(described_class.taps_to_untap).to eql(%w[z])
    end

    it "ignores unavailable formulae when computing which taps to keep" do
      allow(Formulary).to \
        receive(:factory).and_raise(TapFormulaUnavailableError.new(Tap.fetch("homebrew/tap"), "foo"))
      allow(Homebrew::Bundle::TapDumper).to \
        receive(:tap_names).and_return(%w[z homebrew/core homebrew/tap])
      expect(described_class.taps_to_untap).to eql(%w[z homebrew/tap])
    end

    it "ignores formulae with .keepme references when computing which formulae to uninstall" do
      name = full_name ="c"
      allow(Homebrew::Bundle::FormulaDumper).to receive(:formulae).and_return([{ name:, full_name: }])
      f = formula(name) { url "#{name}-1.0" }
      stub_formula_loader f, name

      keg = instance_double(Keg)
      allow(keg).to receive(:keepme_refs).and_return(["/some/file"])
      allow(f).to receive(:installed_kegs).and_return([keg])

      expect(described_class.formulae_to_uninstall).to be_empty
    end

    it "computes which VSCode extensions to uninstall" do
      allow(Homebrew::Bundle::VscodeExtensionDumper).to receive(:extensions).and_return(%w[z])
      expect(described_class.vscode_extensions_to_uninstall).to eql(%w[z])
    end

    it "computes which VSCode extensions to uninstall irrespective of case of the extension name" do
      allow(Homebrew::Bundle::VscodeExtensionDumper).to receive(:extensions).and_return(%w[z vscodeextension1])
      expect(described_class.vscode_extensions_to_uninstall).to eql(%w[z])
    end

    it "computes which flatpaks to uninstall", :needs_linux do
      allow_any_instance_of(Pathname).to receive(:read).and_return <<~EOS
        flatpak 'org.gnome.Calculator'
      EOS
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(true)
      allow(Homebrew::Bundle::FlatpakDumper).to receive(:packages).and_return(%w[org.gnome.Calculator
                                                                                 org.mozilla.firefox])
      expect(described_class.flatpaks_to_uninstall).to eql(%w[org.mozilla.firefox])
    end
  end

  context "when there are no formulae to uninstall and no taps to untap" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
    end

    it "does nothing" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true)
    end
  end

  context "when there are casks to uninstall" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             %w[a b],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
    end

    it "uninstalls casks" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--cask", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true) }.to output(/Uninstalled 2 casks/).to_stdout
    end

    it "does not uninstall casks if --formulae is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true, casks: false) }.not_to output.to_stdout
    end
  end

  context "when there are casks to zap" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             %w[a b],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
    end

    it "uninstalls casks" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--cask", "--zap", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true, zap: true) }.to output(/Uninstalled 2 casks/).to_stdout
    end

    it "does not uninstall casks if --casks is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true, zap: true, casks: false) }.not_to output.to_stdout
    end
  end

  context "when there are formulae to uninstall" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          %w[a b],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
    end

    it "uninstalls formulae" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true) }.to output(/Uninstalled 2 formulae/).to_stdout
    end

    it "does not uninstall formulae if --casks is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true, formulae: false) }.not_to output.to_stdout
    end
  end

  context "when there are taps to untap" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  %w[a b],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
    end

    it "untaps taps" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "untap", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true)
    end

    it "does not untap taps if --taps is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true, taps: false)
    end
  end

  context "when there are VSCode extensions to uninstall" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:which_vscode).and_return(Pathname("code"))
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: %w[GitHub.codespaces],
                                                 flatpaks_to_uninstall:          [])
    end

    it "uninstalls extensions" do
      expect(Kernel).to receive(:system).with("code", "--uninstall-extension", "GitHub.codespaces")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true)
    end

    it "does not uninstall extensions if --vscode is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true, vscode: false)
    end
  end

  context "when there are flatpaks to uninstall", :needs_linux do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          %w[org.gnome.Calculator])
    end

    it "uninstalls flatpaks" do
      expect(Kernel).to receive(:system).with("flatpak", "uninstall", "-y", "--system", "org.gnome.Calculator")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.run(force: true) }.to output(/Uninstalled 1 flatpak/).to_stdout
    end

    it "does not uninstall flatpaks if --flatpak is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.run(force: true, flatpak: false)
    end
  end

  context "when there are casks and formulae to uninstall and taps to untap but without passing `--force`" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             %w[a b],
                                                 formulae_to_uninstall:          %w[a b],
                                                 taps_to_untap:                  %w[a b],
                                                 vscode_extensions_to_uninstall: %w[a b],
                                                 flatpaks_to_uninstall:          %w[a b])
    end

    it "lists casks, formulae and taps" do
      expect(Formatter).to receive(:columns).with(%w[a b]).exactly(5).times.and_return("a b")
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      output_pattern = Regexp.new(
        "Would uninstall casks:.*Would uninstall formulae:.*Would untap:.*" \
        "Would uninstall VSCode extensions:.*Would uninstall flatpaks:",
        Regexp::MULTILINE,
      )
      expect do
        described_class.run
      end.to raise_error(SystemExit)
        .and output(output_pattern).to_stdout
    end
  end

  context "when there is brew cleanup output" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall:             [],
                                                 formulae_to_uninstall:          [],
                                                 taps_to_untap:                  [],
                                                 vscode_extensions_to_uninstall: [],
                                                 flatpaks_to_uninstall:          [])
    end

    define_method(:sane?) do
      expect(described_class).to receive(:system_output_no_stderr).and_return("cleaned")
    end

    context "with --force" do
      it "prints output" do
        sane?
        expect { described_class.run(force: true) }.to output(/cleaned/).to_stdout
      end
    end

    context "without --force" do
      it "prints output" do
        sane?
        expect { described_class.run }.to output(/cleaned/).to_stdout
      end
    end
  end

  describe "#system_output_no_stderr" do
    it "shells out" do
      expect(IO).to receive(:popen).and_return(StringIO.new("true"))
      described_class.system_output_no_stderr("true")
    end
  end

  context "when running with force" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(
        casks_to_uninstall:             [],
        formulae_to_uninstall:          %w[some_formula],
        taps_to_untap:                  [],
        vscode_extensions_to_uninstall: [],
        flatpaks_to_uninstall:          [],
      )
      allow(Kernel).to receive(:system)
      allow(described_class).to receive(:system_output_no_stderr).and_return("")
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
    end

    it "marks Brewfile formulae as installed_on_request before uninstalling" do
      expect(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      described_class.run(force: true)
    end
  end
end
