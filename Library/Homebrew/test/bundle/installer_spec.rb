# typed: true
# frozen_string_literal: true

require "bundle"
require "attestation"
require "bundle/dsl"
require "bundle/installer"
require "trust"
require "formulary"

RSpec.describe Homebrew::Bundle::Installer do
  let(:formula_entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }
  let(:second_formula_entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "redis") }
  let(:cask_options) { { args: {}, full_name: "homebrew/cask/google-chrome" } }
  let(:cask_entry) { Homebrew::Bundle::Dsl::Entry.new(:cask, "google-chrome", cask_options) }
  let(:flatpak_entry) do
    Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.gnome.Calculator", { remote: "flathub" })
  end

  before do
    described_class.reset!
    allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(false)
    allow(Homebrew::Bundle::Brew).to receive_messages(formula_upgradable?: false, install!: true)
    allow(Homebrew::Bundle::Brew).to receive_messages(formula_installed_and_up_to_date?: false,
                                                      preinstall!:                       true)
    allow(Homebrew::Bundle::Cask).to receive_messages(cask_upgradable?: false, install!: true)
    allow(Homebrew::Bundle::Cask).to receive_messages(cask_installed_and_up_to_date?: false,
                                                      installable_or_upgradable?:     true,
                                                      preinstall!:                    true)
    allow(Homebrew::Bundle::Tap).to receive_messages(preinstall!: true, install!: true, installed_taps: [])
    allow(Formula).to receive(:[]) { |name| instance_double(Formula, full_name: name, tap: CoreTap.instance) }
    allow(::Cask::CaskLoader).to receive(:load)
      .and_return(instance_double(::Cask::Cask, full_name: "google-chrome",
                                                tap:       CoreCaskTap.instance))
    # Formula and cask entries share one batched `brew install`, so specs asserting a
    # specific `Bundle.brew` call need the others to fall through to a stub.
    allow(Homebrew::Bundle).to receive(:brew).and_return(true)
    # Entries can name a tap the Brewfile does not, which is otherwise cloned for real.
    allow_any_instance_of(::Tap).to receive(:ensure_installed!)
  end

  it "resets cached package state before installing" do
    expect(Homebrew::Bundle::Cask).to receive(:casks).twice.and_return(
      [double(to_s: "stale")],
      [double(to_s: "google-chrome")],
    )

    expect(Homebrew::Bundle::Cask.cask_names).to eq(["stale"])

    described_class.reset!
    described_class.install!([cask_entry], verbose: false, force: false, quiet: true)
  end

  it "fetches and installs formulae and casks in one `brew install`" do
    expect(Homebrew::Bundle).to receive(:brew)
      .with("install", "--adopt", "homebrew/core/mysql", "homebrew/cask/google-chrome", verbose: false)
      .once.and_return(true)

    described_class.install!([formula_entry, cask_entry], quiet: true)
  end

  it "does not run a separate fetch" do
    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([formula_entry], quiet: true)
  end

  it "fails a missing Flatpak entry without skipping following entries or claiming success" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "example/tap")
    allow(Homebrew::Bundle::Flatpak).to receive(:package_manager_executable).and_return(nil)
    expect(Homebrew::Bundle::Tap).to receive(:preinstall!)
      .with("example/tap", no_upgrade: false, verbose: false)
      .and_return(true)
    expect(Homebrew::Bundle::Tap).to receive(:install!)
      .with("example/tap", preinstall: true, no_upgrade: false, verbose: false, force: false)
      .and_return(true)

    result = T.let(nil, T.nilable(T::Boolean))
    expect do
      result = described_class.install!([flatpak_entry, tap_entry], quiet: false)
    end.to output(
      /flatpak is not installed.*Installing org\.gnome\.Calculator has failed!.*`brew bundle` failed!/m,
    ).to_stderr.and not_to_output(/Using org\.gnome\.Calculator/).to_stdout
    expect(result).to be(false)
  end

  it "trusts `trusted: true` formulae before loading them" do
    trusted_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "thirdparty/tap/bar", { trusted: true })

    allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["thirdparty/tap"])

    expect(Homebrew::Trust).to receive(:trust!).with(:formula, "thirdparty/tap/bar").ordered.and_return(true)
    expect(Formula).to receive(:[]).with("thirdparty/tap/bar").ordered
                                   .and_return(instance_double(Formula, full_name: "thirdparty/tap/bar",
                                                                        tap:       Tap.fetch("thirdparty/tap")))

    described_class.install!([trusted_formula_entry], quiet: true)
  end

  it "trusts `trusted: true` casks before loading them" do
    options = { args: {}, full_name: "thirdparty/tap/baz", trusted: true }
    trusted_cask_entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "baz", options)

    allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["thirdparty/tap"])

    expect(Homebrew::Trust).to receive(:trust!).with(:cask, "thirdparty/tap/baz").ordered.and_return(true)
    expect(::Cask::CaskLoader).to receive(:load).with("thirdparty/tap/baz").ordered
                                                .and_return(instance_double(::Cask::Cask,
                                                                            full_name: "thirdparty/tap/baz",
                                                                            tap:       Tap.fetch("thirdparty/tap")))

    described_class.install!([trusted_cask_entry], quiet: true)
  end

  it "trusts `trusted: true` taps by name" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "thirdparty/tap", { trusted: true })

    expect(Homebrew::Trust).to receive(:trust!).with(:tap, "thirdparty/tap").and_return(true)

    described_class.install!([tap_entry], quiet: true)
  end

  it "trusts `trusted: true` taps with a clone target by their remote reference" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(
      :tap, "thirdparty/custom", { clone_target: "https://github.com/thirdparty/homebrew-custom", trusted: true }
    )

    expect(Homebrew::Trust).to receive(:trust!).with(:tap, "thirdparty/custom").and_return(true)

    described_class.install!([tap_entry], quiet: true)
  end

  it "trusts tap `trusted` hash entries" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(
      :tap, "thirdparty/tap",
      {
        trusted: {
          formula:  "foo",
          formulae: ["bar"],
          cask:     "baz",
          casks:    ["qux"],
          command:  "hello",
          commands: ["world"],
        },
      }
    )

    expect(Homebrew::Trust).to receive(:trust!).with(:formula, "thirdparty/tap/foo").and_return(true)
    expect(Homebrew::Trust).to receive(:trust!).with(:formula, "thirdparty/tap/bar").and_return(true)
    expect(Homebrew::Trust).to receive(:trust!).with(:cask, "thirdparty/tap/baz").and_return(true)
    expect(Homebrew::Trust).to receive(:trust!).with(:cask, "thirdparty/tap/qux").and_return(true)
    expect(Homebrew::Trust).to receive(:trust!).with(:command, "thirdparty/tap/hello").and_return(true)
    expect(Homebrew::Trust).to receive(:trust!).with(:command, "thirdparty/tap/world").and_return(true)

    described_class.install!([tap_entry], quiet: true)
  end

  it "rejects unsupported tap `trusted` hash keys" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "thirdparty/tap", { trusted: { tap: "foo" } })

    expect { described_class.install!([tap_entry], quiet: true) }
      .to raise_error(UsageError, /Unsupported trusted keys: tap/)
  end

  it "does not trust unqualified `trusted: true` names" do
    trusted_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql", { trusted: true })

    expect(Homebrew::Bundle::Trust.entries([trusted_formula_entry])).to be_empty
  end

  describe "batched Homebrew installation" do
    before do
      allow(Homebrew::Bundle).to receive(:brew).and_return(true)
    end

    it "installs formulae needing installation in a single `brew install`" do
      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "homebrew/core/mysql", "homebrew/core/redis", verbose: false)
        .and_return(true)

      described_class.install!([formula_entry, second_formula_entry], quiet: true)
    end

    it "installs and upgrades formulae in a single `brew install`" do
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed?).with("mysql").and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed?).with("redis").and_return(true)

      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "homebrew/core/mysql", "homebrew/core/redis", verbose: false)
        .and_return(true)

      described_class.install!([formula_entry, second_formula_entry], quiet: true)
    end

    it "counts every entry of a successful batch as installed" do
      expect(described_class.install!([formula_entry, second_formula_entry], quiet: true)).to be(true)
    end

    it "attributes a failed batch to the entries that are not installed afterwards" do
      allow(Homebrew::Bundle).to receive(:brew).with("install", any_args).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
        .with("mysql", no_upgrade: false).and_return(true)
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
        .with("redis", no_upgrade: false).and_return(false)

      expect do
        expect(described_class.install!([formula_entry, second_formula_entry], quiet: true)).to be(false)
      end.to output(/Installing redis has failed!/).to_stderr
    end

    it "refreshes the cached view of what is installed before finishing each entry" do
      expect(Homebrew::Bundle::Brew).to receive(:reset!).and_call_original.ordered
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("mysql", preinstall: false, no_upgrade: false, verbose: false, force: false)
        .ordered
        .and_return(true)

      described_class.install!([formula_entry], quiet: true)
    end

    it "keeps an entry carrying options out of the batch" do
      service_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "redis", { restart_service: :changed })

      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "homebrew/core/mysql", verbose: false)
        .and_return(true)
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("redis", restart_service: :changed, preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([formula_entry, service_entry], quiet: true)
    end

    it "keeps an unloadable formula out of the batch" do
      allow(Formula).to receive(:[]).with("mysql").and_raise(FormulaUnavailableError, "mysql")

      expect(Homebrew::Bundle).not_to receive(:brew).with("install", any_args)
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("mysql", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([formula_entry], quiet: true)
    end

    it "keeps an already up-to-date entry out of the batch but still finishes it" do
      allow(Homebrew::Bundle::Brew).to receive(:preinstall!).with("mysql", any_args).and_return(false)

      expect(Homebrew::Bundle).not_to receive(:brew).with("install", any_args)
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("mysql", preinstall: false, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      expect { described_class.install!([formula_entry], quiet: false) }.to output(/Using mysql/).to_stdout
    end

    it "batches casks with Homebrew's native download queue" do
      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "--adopt", "homebrew/cask/google-chrome", verbose: false)
        .and_return(true)
      expect(Homebrew::Bundle::Cask).to receive(:install!)
        .with("google-chrome", **cask_options, preinstall: false, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([cask_entry], quiet: true)
    end

    it "installs a cask sharing a token with a formula as a cask" do
      options = { args: {}, full_name: "ambiguous" }
      entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "ambiguous", options)
      allow(::Cask::CaskLoader).to receive(:load)
        .with("ambiguous")
        .and_return(instance_double(::Cask::Cask, full_name: "ambiguous", tap: CoreCaskTap.instance))

      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "--adopt", "homebrew/cask/ambiguous", verbose: false)
        .and_return(true)

      described_class.install!([entry], quiet: true)
    end

    it "uses the resolved formula name when batching an alias" do
      allow(Formula).to receive(:[]).with("mysql").and_return(instance_double(Formula, full_name: "mysql@9.7",
                                                                                       tap:       CoreTap.instance))

      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "homebrew/core/mysql@9.7", verbose: false)
        .and_return(true)

      described_class.install!([formula_entry], quiet: true)
    end

    it "preserves third-party tap names in a mixed batch" do
      allow(Formula).to receive(:[]).with("mysql")
                                    .and_return(instance_double(Formula, full_name: "thirdparty/tap/mysql",
                                                                         tap:       Tap.fetch("thirdparty/tap")))
      allow(::Cask::CaskLoader).to receive(:load)
        .and_return(instance_double(::Cask::Cask, full_name: "thirdparty/tap/google-chrome",
                                                  tap:       Tap.fetch("thirdparty/tap")))

      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "--adopt", "thirdparty/tap/mysql", "thirdparty/tap/google-chrome", verbose: false)
        .once.and_return(true)

      described_class.install!([formula_entry, cask_entry], quiet: true)
    end

    [:brew, :cask].each do |type|
      it "preserves a tapless #{type} name" do
        T.bind(self, RSpec::Core::ExampleGroup)

        entry = Homebrew::Bundle::Dsl::Entry.new(type, "local")
        if type == :brew
          allow(Formula).to receive(:[]).with("local")
                                        .and_return(instance_double(Formula, full_name: "local", tap: nil))
        else
          allow(::Cask::CaskLoader).to receive(:load).with("local")
                                                     .and_return(instance_double(::Cask::Cask, full_name: "local",
                                                                                               tap:       nil))
        end

        expect(Homebrew::Bundle.installable(type)).to receive(:install!)
          .with("local", preinstall: true, no_upgrade: false, verbose: false, force: false).and_return(true)

        described_class.install!([entry], quiet: true)
      end
    end

    ["thirdparty/tap/collision", "collision"].product([false, true], [false, true]).each do |name, force, success|
      it "installs the colliding #{name} cask with an explicit type (force: #{force}, success: #{success})" do
        T.bind(self, RSpec::Core::ExampleGroup)

        tap = Tap.fetch("thirdparty/tap") if name.include?("/")
        if tap
          allow(tap).to receive(:formula_dir).and_return(mktmpdir)
          (tap.formula_dir/"collision.rb").write("class WrongClass < Formula; end")
        end
        allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["thirdparty/tap"])
        allow(::Cask::CaskLoader).to receive(:load).with(name)
                                                   .and_return(instance_double(Cask::Cask, full_name: name, tap:))
        expect(Formulary).not_to receive(:factory)
        allow(Homebrew::Bundle::Cask).to receive(:install!).and_call_original
        allow(Homebrew::Bundle::Cask).to receive(:cask_installed?).and_return(false)

        expect(Homebrew::Bundle).to receive(:brew)
          .with("install", *(["--force", "--overwrite"] if force), "homebrew/core/mysql", verbose: false)
          .ordered.and_return(true)
        expect(Homebrew::Bundle).to receive(:brew)
          .with("install", "--cask", name, force ? "--force" : "--adopt", verbose: false)
          .ordered.and_return(success)

        expect do
          expect(described_class.install!([
            Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql"),
            Homebrew::Bundle::Dsl::Entry.new(:cask, name),
          ], force:, quiet: true)).to be(success)
        end.to output(success ? "" : /Installing #{name} has failed!/).to_stderr
      end
    end

    it "keeps a cask matching a formula alias out of the batch without loading the formula" do
      tap = Tap.fetch("thirdparty/tap")
      allow(tap).to receive_messages(formula_dir: mktmpdir, alias_dir: mktmpdir)
      (tap.formula_dir/"foo.rb").write("class WrongClass < Formula; end")
      (tap.alias_dir/"google-chrome").make_symlink(tap.formula_dir/"foo.rb")
      allow(::Cask::CaskLoader).to receive(:load)
        .and_return(instance_double(Cask::Cask, full_name: "thirdparty/tap/google-chrome", tap:))

      expect(Formulary).not_to receive(:factory)
      expect(Homebrew::Bundle::Cask).to receive(:install!)
        .with("google-chrome", **cask_options, preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([cask_entry], quiet: true)
    end

    it "installs a formula sharing a cask token with an explicit type" do
      tap = Tap.fetch("thirdparty/tap")
      allow(tap).to receive(:cask_dir).and_return(mktmpdir)
      (tap.cask_dir/"collision.rb").write('raise "Do not load this cask"')
      allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return([tap.name])
      allow(Formula).to receive(:[]).with("thirdparty/tap/collision")
                                    .and_return(instance_double(Formula, full_name: "thirdparty/tap/collision", tap:))
      allow(Homebrew::Bundle::Brew).to receive(:install!).and_call_original
      allow(Homebrew::Bundle::Brew).to receive_messages(formula_installed?: false, formulae_by_full_name: nil,
                                                        installed_formulae: [])

      expect(::Cask::CaskLoader).not_to receive(:load)
      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "--formula", "thirdparty/tap/collision", verbose: false).and_return(true)

      expect do
        described_class.install!([Homebrew::Bundle::Dsl::Entry.new(:brew, "thirdparty/tap/collision")], quiet: true)
      end.not_to output.to_stderr
    end

    it "forces formulae and casks in one batch" do
      expect(Homebrew::Bundle).to receive(:brew)
        .with("install", "--force", "--overwrite", "homebrew/core/mysql",
              "homebrew/cask/google-chrome", verbose: false)
        .once.and_return(true)

      described_class.install!([formula_entry, cask_entry], force: true, quiet: true)
    end

    it "finishes installed casks when a mixed batch fails" do
      allow(Homebrew::Bundle).to receive(:brew).with("install", any_args).and_return(false)
      allow(Homebrew::Bundle::Cask).to receive(:cask_installed_and_up_to_date?).and_return(true)

      expect(Homebrew::Bundle::Cask).to receive(:install!)
        .with("google-chrome", **cask_options, preinstall: false, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([formula_entry, cask_entry], quiet: true)
    end

    it "attributes a failed batch to casks that are not installed afterwards" do
      allow(Homebrew::Bundle).to receive(:brew).with("install", any_args).and_return(false)

      expect do
        expect(described_class.install!([cask_entry], quiet: true)).to be(false)
      end.to output(/Installing google-chrome has failed!/).to_stderr
    end

    it "keeps a cask with arguments out of the batch" do
      options = cask_options.merge(args: { appdir: "/Applications" })
      entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "google-chrome", options)

      expect(Homebrew::Bundle).not_to receive(:brew).with("install", any_args)
      expect(Homebrew::Bundle::Cask).to receive(:install!)
        .with("google-chrome", **options, preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([entry], quiet: true)
    end

    it "keeps an unloadable cask out of the batch" do
      allow(::Cask::CaskLoader).to receive(:load).with("homebrew/cask/google-chrome")
                                                 .and_raise(::Cask::CaskUnavailableError, "google-chrome")

      expect(Homebrew::Bundle).not_to receive(:brew).with("install", any_args)
      expect(Homebrew::Bundle::Cask).to receive(:install!)
        .with("google-chrome", **cask_options, preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      described_class.install!([cask_entry], quiet: true)
    end

    it "preserves upgrades when `HOMEBREW_NO_INSTALL_UPGRADE` is set" do
      ENV["HOMEBREW_NO_INSTALL_UPGRADE"] = "1"

      expect(Homebrew::Bundle).to receive(:brew) do |*args, **options|
        expect(args).to eq(["install", "homebrew/core/mysql"])
        expect(options).to eq(verbose: false)
        expect(ENV.fetch("HOMEBREW_NO_INSTALL_UPGRADE", nil)).to be_nil
        true
      end

      described_class.install!([formula_entry], quiet: true)
    end

    it "installs Brewfile taps before batching the formulae" do
      tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "homebrew/foo")
      order = []
      allow(Homebrew::Bundle::Tap).to receive(:install!) do |name, **_options|
        order << name
        true
      end
      allow(Homebrew::Bundle).to receive(:brew) do |*args, **_options|
        order << args.first
        true
      end

      described_class.install!([formula_entry, tap_entry], quiet: true)

      expect(order).to eq(["homebrew/foo", "install"])
    end

    it "resolves `gh` before installing anything when verifying attestations" do
      order = []
      allow(Homebrew::EnvConfig).to receive(:verify_attestations?).and_return(true)
      allow(Homebrew::Attestation).to receive(:gh_executable) do
        order << "gh"
        Pathname("/fake/gh")
      end
      allow(Homebrew::Bundle).to receive(:brew) do |*args, **_options|
        order << args.first
        true
      end

      described_class.install!([formula_entry], quiet: true)

      expect(order).to include("gh")
      expect(order.index("gh")).to be < order.index("install")
    end
  end

  describe "native extension batches" do
    it "delegates entries to an extension that registers batch support" do
      first_entry = Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript")
      second_entry = Homebrew::Bundle::Dsl::Entry.new(:npm, "prettier")
      allow(Homebrew::Bundle::Npm).to receive_messages(preinstall!: true, reset!: nil)

      expect(Homebrew::Bundle::Npm).to receive(:install_batch!)
        .with([first_entry, second_entry], verbose: false)
        .and_return(true)
      expect(Homebrew::Bundle::Npm).not_to receive(:install!)

      expect(described_class.install!([first_entry, second_entry], quiet: true)).to be(true)
    end

    it "retries only entries left uninstalled by a failed native batch" do
      first_entry = Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript")
      second_entry = Homebrew::Bundle::Dsl::Entry.new(:npm, "prettier")
      allow(Homebrew::Bundle::Npm).to receive(:preinstall!).with("typescript", any_args).and_return(true, false)
      allow(Homebrew::Bundle::Npm).to receive(:preinstall!).with("prettier", any_args).and_return(true, true)
      allow(Homebrew::Bundle::Npm).to receive(:install_batch!).and_return(false)
      expect(Homebrew::Bundle::Npm).not_to receive(:install!).with("typescript", any_args)
      expect(Homebrew::Bundle::Npm).to receive(:install!)
        .with("prettier", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(false)

      expect do
        expect(described_class.install!([first_entry, second_entry], quiet: true)).to be(false)
      end.to output(/Installing prettier has failed!/).to_stderr
    end
  end
end
