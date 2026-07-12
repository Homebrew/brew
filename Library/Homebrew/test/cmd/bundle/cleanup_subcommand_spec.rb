# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/cleanup"
require "trust"
require "utils"

RSpec.describe Homebrew::Cmd::Bundle::CleanupSubcommand do
  describe "#run" do
    it "asks before cleanup unless --force is passed" do
      args = args_for_subcommand(:cleanup, all?: false, formulae?: false, casks?: false, taps?: false, mas?: false,
                                           vscode?: false, cargo?: false, flatpak?: false, go?: false, krew?: false,
                                           npm?: false, uv?: false)
      context = bundle_subcommand_context(:cleanup)

      expect(described_class).to receive(:cleanup).with(hash_including(ask:   true,
                                                                       force: false))

      described_class.new(args, context:).run
    end

    it "does not ask before cleanup when --force is passed" do
      args = args_for_subcommand(:cleanup, all?: false, formulae?: false, casks?: false, taps?: false, mas?: false,
                                           vscode?: false, cargo?: false, flatpak?: false, go?: false, krew?: false,
                                           npm?: false, uv?: false)
      context = bundle_subcommand_context(:cleanup, force: true)

      expect(described_class).to receive(:cleanup).with(hash_including(ask:   false,
                                                                       force: true))

      described_class.new(args, context:).run
    end

    it "cleans up every supported type when --all is passed" do
      args = args_for_subcommand(:cleanup, all?: true, formulae?: false, casks?: false, taps?: false, mas?: false,
                                           vscode?: false, cargo?: false, flatpak?: false, go?: false, krew?: false,
                                           npm?: false, uv?: false)
      context = bundle_subcommand_context(:cleanup, no_type_args: false)

      expect(described_class).to receive(:cleanup) do |formulae:, casks:, taps:, extension_types:, **|
        expect(formulae).to be(true)
        expect(casks).to be(true)
        expect(taps).to be(true)
        expect(extension_types).to include(
          cargo:   true,
          flatpak: true,
          go:      true,
          krew:    true,
          mas:     true,
          npm:     true,
          uv:      true,
          vscode:  true,
        )
      end

      described_class.new(args, context:).run
    end

    it "does not clean up disabled types by default" do
      args = args_for_subcommand(:cleanup, no_formulae?: true, no_mas?: true)
      context = bundle_subcommand_context(:cleanup)

      expect(described_class).to receive(:cleanup) do |formulae:, casks:, taps:, extension_types:, **|
        expect(formulae).to be(false)
        expect(casks).to be(true)
        expect(taps).to be(true)
        expect(extension_types[:mas]).to be(false)
        expect(extension_types[:vscode]).to be(true)
      end

      described_class.new(args, context:).run
    end

    it "treats --no-tap as --no-cleanup-tap" do
      args = args_for_subcommand(:cleanup, no_taps?: true)
      context = bundle_subcommand_context(:cleanup)

      expect(described_class).to receive(:cleanup) do |taps:, **|
        expect(taps).to be(false)
      end

      described_class.new(args, context:).run
    end

    it "does not clean up types disabled by environment" do
      args = args_for_subcommand(:cleanup, no_cleanup_brew?: true, no_cleanup_mas?: true)
      context = bundle_subcommand_context(:cleanup)

      expect(described_class).to receive(:cleanup) do |formulae:, casks:, taps:, extension_types:, **|
        expect(formulae).to be(false)
        expect(casks).to be(true)
        expect(taps).to be(true)
        expect(extension_types[:mas]).to be(false)
        expect(extension_types[:vscode]).to be(true)
      end

      described_class.new(args, context:).run
    end
  end

  describe "read Brewfile and current installation", :no_api do
    before do
      described_class.reset!

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      allow_any_instance_of(Pathname).to receive(:read).and_return <<~RUBY
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
      RUBY
      described_class.read_dsl_from_brewfile!
      %w[a b d2 homebrew/tap/f homebrew/tap/g homebrew/tap/h homebrew/tap/i2
         homebrew/tap/hasdependency hasbuilddependency1 hasbuilddependency2].each do |full_name|
        tap_name = Utils.tap_from_full_name(full_name)
        name = Utils.name_from_full_name(full_name)
        tap = (Tap.fetch(tap_name) if tap_name.present?)
        f = formula(name, tap:) do
          T.bind(self, T.class_of(Formula))
          url "#{name}-1.0"
        end
        stub_formula_loader f, full_name
      end
    end

    it "computes which casks to uninstall" do
      cask_123 = instance_double(Cask::Cask, to_s: "123", old_tokens: [])
      cask_456 = instance_double(Cask::Cask, to_s: "456", old_tokens: [])
      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([cask_123, cask_456])
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
      allow(Homebrew::Bundle::Brew).to receive(:formulae).and_return(formulae_hash)

      formulae_hash.each do |hash_formula|
        name = hash_formula[:name]
        full_name = hash_formula[:full_name]
        tap_name = Utils.tap_from_full_name(full_name) || "homebrew/core"
        tap = Tap.fetch(tap_name)
        f = formula(name, tap:) do
          T.bind(self, T.class_of(Formula))
          url "#{name}-1.0"
        end
        stub_formula_loader f, full_name
      end

      allow(Homebrew::Bundle::Cask).to receive(:formula_dependencies).and_return(%w[caskdependency])
      expect(described_class.formulae_to_uninstall).to eql %w[
        c
        homebrew/tap/e
        other/tap/h
        builddependency1
      ]
    end

    it "computes which tap to untap" do
      allow(Homebrew::Bundle::Tap).to \
        receive(:tap_names).and_return(%w[z homebrew/core homebrew/tap])
      expect(described_class.taps_to_untap).to eql(%w[z])
    end

    it "keeps taps referenced by fully qualified formulae" do
      allow_any_instance_of(Pathname).to receive(:read).and_return <<~RUBY
        brew "homebrew/tap/foo"
      RUBY
      described_class.read_dsl_from_brewfile!

      allow(Homebrew::Bundle::Brew).to receive(:formulae).and_return([
        { name: "foo", full_name: "homebrew/tap/foo", dependencies: [], build_dependencies: [] },
      ])
      stub_formula_loader formula("foo", tap: Tap.fetch("homebrew/tap")) {
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      }, "homebrew/tap/foo"
      allow(Homebrew::Bundle::Tap).to \
        receive(:tap_names).and_return(%w[homebrew/core homebrew/tap])

      expect(described_class.formulae_to_uninstall).to be_empty
      expect(described_class.taps_to_untap).to be_empty
    end

    it "keeps taps referenced by fully qualified casks" do
      allow_any_instance_of(Pathname).to receive(:read).and_return <<~RUBY
        cask "homebrew/tap/foo"
      RUBY
      described_class.read_dsl_from_brewfile!

      allow(Homebrew::Bundle::Cask).to receive(:casks).and_return([
        instance_double(Cask::Cask, to_s: "foo", old_tokens: [], depends_on: {}),
      ])
      allow(Homebrew::Bundle::Brew).to receive(:formulae).and_return([])
      allow(Homebrew::Bundle::Tap).to \
        receive(:tap_names).and_return(%w[homebrew/core homebrew/tap])

      expect(described_class.casks_to_uninstall).to be_empty
      expect(described_class.taps_to_untap).to be_empty
    end

    it "ignores unavailable formulae when computing which taps to keep" do
      allow_any_instance_of(Pathname).to receive(:read).and_return <<~RUBY
        brew "foo"
      RUBY
      described_class.read_dsl_from_brewfile!

      allow(Formulary).to \
        receive(:factory).and_raise(TapFormulaUnavailableError.new(Tap.fetch("homebrew/tap"), "foo"))
      allow(Homebrew::Bundle::Tap).to \
        receive(:tap_names).and_return(%w[z homebrew/core homebrew/tap])
      expect(described_class.taps_to_untap).to eql(%w[z homebrew/tap])
    end

    it "ignores formulae with .keepme references when computing which formulae to uninstall" do
      name = full_name ="c"
      allow(Homebrew::Bundle::Brew).to receive(:formulae).and_return([{ name:, full_name: }])
      f = formula(name) do
        T.bind(self, T.class_of(Formula))
        url "#{name}-1.0"
      end
      stub_formula_loader f, name

      keg = instance_double(Keg)
      allow(keg).to receive(:keepme_refs).and_return(["/some/file"])
      allow(f).to receive(:installed_kegs).and_return([keg])

      expect(described_class.formulae_to_uninstall).to be_empty
    end

    it "computes which VSCode extensions to uninstall" do
      allow(Homebrew::Bundle::VscodeExtension).to receive(:extensions).and_return(%w[z])
      expect(Homebrew::Bundle::VscodeExtension.cleanup_items(described_class.dsl.entries)).to eql(%w[z])
    end

    it "computes which VSCode extensions to uninstall irrespective of case of the extension name" do
      allow(Homebrew::Bundle::VscodeExtension).to receive(:extensions).and_return(%w[z vscodeextension1])
      expect(Homebrew::Bundle::VscodeExtension.cleanup_items(described_class.dsl.entries)).to eql(%w[z])
    end

    it "computes which flatpaks to uninstall", :needs_linux do
      allow_any_instance_of(Pathname).to receive(:read).and_return <<~RUBY
        flatpak 'org.gnome.Calculator'
      RUBY
      described_class.read_dsl_from_brewfile!
      allow(Homebrew::Bundle::Flatpak).to receive_messages(
        package_manager_installed?: true,
        packages:                   %w[org.gnome.Calculator org.mozilla.firefox],
      )
      expect(Homebrew::Bundle::Flatpak.cleanup_items(described_class.dsl.entries)).to eql(%w[org.mozilla.firefox])
    end
  end

  context "when there are no formulae to uninstall and no taps to untap" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: [],
                                                 formulae_to_uninstall: [], taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    it "does nothing" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true)
    end
  end

  context "when there are trusted Brewfile entries", :trust_store do
    let(:dsl) do
      Homebrew::Bundle::Dsl.new(StringIO.new(<<~RUBY))
        tap "trusted/tap", trusted: true
        tap "thirdparty/tap", trusted: {
          formula: "foo",
          casks: ["bar"],
          command: "baz",
        }
        brew "thirdparty/tap/qux", trusted: true
        cask "thirdparty/tap/quux", trusted: true
      RUBY
    end

    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall: [],
                                                 formulae_to_uninstall: [], taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
      allow(described_class).to receive(:system_output_no_stderr).and_return("")

      Homebrew::Trust.trust!(:tap, "old/tap")
      Homebrew::Trust.trust!(:formula, "old/tap/foo")
      Homebrew::Trust.trust!(:cask, "old/tap/bar")
      Homebrew::Trust.trust!(:command, "old/tap/baz")
    end

    it "resets the trust store to the Brewfile entries on forced cleanup" do
      described_class.cleanup(force: true, dsl:)

      expect(Homebrew::Trust.trusted_entries(:tap)).to eq(["trusted/tap"])
      expect(Homebrew::Trust.trusted_entries(:formula)).to eq(%w[thirdparty/tap/foo thirdparty/tap/qux])
      expect(Homebrew::Trust.trusted_entries(:cask)).to eq(%w[thirdparty/tap/bar thirdparty/tap/quux])
      expect(Homebrew::Trust.trusted_entries(:command)).to eq(["thirdparty/tap/baz"])
    end
  end

  context "when there are casks to uninstall" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: %w[a b], formulae_to_uninstall: [],
                                                 taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    it "uninstalls casks" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--cask", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true)
      end.to output(/Uninstalled 2 casks/).to_stdout
    end

    it "does not uninstall casks if --formulae is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect { described_class.cleanup(force: true, casks: false) }.not_to output.to_stdout
    end
  end

  context "when there are casks to zap" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: %w[a b], formulae_to_uninstall: [],
                                                 taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    it "uninstalls casks" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--cask", "--zap", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true, zap: true)
      end.to output(/Uninstalled 2 casks/).to_stdout
    end

    it "does not uninstall casks if --casks is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true, zap: true, casks: false)
      end.not_to output.to_stdout
    end
  end

  context "when there are formulae to uninstall" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(casks_to_uninstall: [], formulae_to_uninstall: %w[a b],
                                                 taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
    end

    it "uninstalls formulae" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true)
      end.to output(/Uninstalled 2 formulae/).to_stdout
    end

    it "does not uninstall formulae if --casks is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true, formulae: false)
      end.not_to output.to_stdout
    end
  end

  context "when there are taps to untap" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: [], formulae_to_uninstall: [],
                                                 taps_to_untap: %w[a b])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    it "untaps taps" do
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "untap", "a", "b")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true)
    end

    it "does not untap taps if --taps is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true, taps: false)
    end
  end

  context "when there are VSCode extensions to uninstall" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: [],
                                                 formulae_to_uninstall: [], taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive_messages(package_manager_executable: Pathname("code"),
                                                                   cleanup_items:              %w[GitHub.codespaces])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    it "uninstalls extensions" do
      expect(Kernel).to receive(:system).with("code", "--uninstall-extension", "GitHub.codespaces")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true)
    end

    it "does not uninstall extensions if --vscode is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true, extension_types: { vscode: false })
    end
  end

  context "when there are flatpaks to uninstall", :needs_linux do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: [],
                                                 formulae_to_uninstall: [], taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return(%w[org.gnome.Calculator])
    end

    it "uninstalls flatpaks" do
      expect(Kernel).to receive(:system).with("flatpak", "uninstall", "-y", "--system", "org.gnome.Calculator")
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      expect do
        described_class.cleanup(force: true)
      end.to output(/Uninstalled 1 flatpak/).to_stdout
    end

    it "does not uninstall flatpaks if --flatpak is disabled" do
      expect(Kernel).not_to receive(:system)
      expect(described_class).to receive(:system_output_no_stderr).and_return("")
      described_class.cleanup(force: true, extension_types: { flatpak: false })
    end
  end

  context "when there are casks and formulae to uninstall and taps to untap but without passing `--force`" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall:    %w[a b],
                                                 formulae_to_uninstall: %w[
                                                   a b
                                                 ],
                                                 taps_to_untap:         %w[
                                                   a b
                                                 ])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return(%w[a b])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return(%w[a b])
    end

    it "lists casks, formulae and taps" do
      expect(Formatter).to receive(:columns).with(%w[a b]).exactly(5).times.and_return("a b")
      expect(Kernel).not_to receive(:system)
      expect(Homebrew::Cleanup).to receive(:dry_run_output).and_return("")
      output_pattern = Regexp.new(
        "Would uninstall casks:.*Would uninstall formulae:.*Would untap:.*" \
        "Would uninstall VSCode extensions:.*Would uninstall flatpaks:",
        Regexp::MULTILINE,
      )
      expect do
        described_class.cleanup
      end.to raise_error(SystemExit)
        .and output(output_pattern).to_stdout
    end

    it "prompts and cleans up when asking" do
      allow($stdin).to receive_messages(getch: "y", tty?: true)
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      allow(Kernel).to receive(:system)
      allow(described_class).to receive(:system_output_no_stderr).and_return("")
      expect(Formatter).to receive(:columns).with(%w[a b]).exactly(5).times.and_return("a b")
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--cask", "--force", "a", "b")
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", "a", "b")
      expect(Kernel).to receive(:system).with(HOMEBREW_BREW_FILE, "untap", "a", "b")
      expect(Homebrew::Cleanup).to receive(:dry_run_output).and_return("")

      expect { described_class.cleanup(ask: true) }.not_to raise_error
    end
  end

  context "when there is brew cleanup output" do
    before do
      described_class.reset!
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
      allow(described_class).to receive_messages(casks_to_uninstall: [],
                                                 formulae_to_uninstall: [], taps_to_untap: [])
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
    end

    define_method(:sane?) do
      expect(described_class).not_to receive(:system_output_no_stderr)
      expect(Homebrew::Cleanup).to receive(:dry_run_output).and_return("cleaned")
    end

    context "with --force" do
      it "prints output" do
        expect(described_class).to receive(:system_output_no_stderr).and_return("cleaned")
        expect { described_class.cleanup(force: true) }.to output(/cleaned/).to_stdout
      end
    end

    context "without --force" do
      it "prints output" do
        sane?
        expect { described_class.cleanup }.to output(<<~EOS).to_stdout
          Would `brew cleanup`:
          cleaned
          Run `brew bundle cleanup --force` to make these changes.
        EOS
      end
    end
  end

  describe "#system_output_no_stderr" do
    it "discards stderr without closing it" do
      stdout = nil
      expect do
        stdout = described_class.system_output_no_stderr(
          RUBY_PATH,
          "-e",
          '$stderr.puts "warning"; $stdout.puts "cleaned"',
        )
      end.not_to output.to_stderr_from_any_process

      expect(stdout).to eq("cleaned\n")
    end

    it "raises when the command fails" do
      expect do
        described_class.system_output_no_stderr(RUBY_PATH, "-e", "exit 1")
      end.to raise_error(ErrorDuringExecution)
    end
  end

  context "when running with force" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(
        casks_to_uninstall:    [],
        formulae_to_uninstall: %w[some_formula],
        taps_to_untap:         [],
      )
      allow(Homebrew::Bundle::VscodeExtension).to receive(:cleanup_items).and_return([])
      allow(Homebrew::Bundle::Flatpak).to receive(:cleanup_items).and_return([])
      allow(Kernel).to receive(:system)
      allow(described_class).to receive(:system_output_no_stderr).and_return("")
      allow_any_instance_of(Pathname).to receive(:read).and_return("")
    end

    it "marks Brewfile formulae as installed_on_request before uninstalling" do
      expect(Homebrew::Bundle).to receive(:mark_as_installed_on_request!)
      described_class.cleanup(force: true)
    end
  end
end
