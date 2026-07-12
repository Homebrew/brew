# typed: true
# frozen_string_literal: true

require "bundle"
require "attestation"
require "bundle/dsl"
require "bundle/installer"
require "bundle/parallel_installer"
require "trust"

RSpec.describe Homebrew::Bundle::Installer do
  let(:formula_entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }
  let(:second_formula_entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "redis") }
  let(:cask_options) { { args: {}, full_name: "homebrew/cask/google-chrome" } }
  let(:cask_entry) { Homebrew::Bundle::Dsl::Entry.new(:cask, "google-chrome", cask_options) }

  before do
    described_class.reset!
    allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(false)
    allow(Homebrew::Bundle::Brew).to receive_messages(formula_upgradable?: false, install!: true)
    allow(Homebrew::Bundle::Brew).to receive_messages(formula_installed_and_up_to_date?: false,
                                                      preinstall!:                       true)
    allow(Homebrew::Bundle::Cask).to receive_messages(cask_upgradable?: false, install!: true)
    allow(Homebrew::Bundle::Cask).to receive_messages(installable_or_upgradable?: true, preinstall!: true)
    allow(Homebrew::Bundle::Tap).to receive_messages(preinstall!: true, install!: true, installed_taps: [])
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

  it "prefetches installable formulae and casks before installing" do
    allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["homebrew/cask"])
    allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
      .with("mysql", no_upgrade: false).and_return(false)
    allow(Homebrew::Bundle::Cask).to receive(:installable_or_upgradable?)
      .with("google-chrome", no_upgrade: false, **cask_options).and_return(true)

    expect(Homebrew::Bundle).to receive(:brew)
      .with("fetch", "mysql", "homebrew/cask/google-chrome", verbose: false)
      .ordered
      .and_return(true)
    expect(Homebrew::Bundle::Brew).to receive(:preinstall!)
      .with("mysql", no_upgrade: false, verbose: false)
      .ordered
      .and_return(true)
    expect(Homebrew::Bundle::Cask).to receive(:preinstall!)
      .with("google-chrome", **cask_options, no_upgrade: false, verbose: false)
      .ordered
      .and_return(true)

    described_class.install!([formula_entry, cask_entry], verbose: false, force: false, quiet: true)
  end

  it "skips fetching when no formulae or casks need installation or upgrade" do
    allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
      .with("mysql", no_upgrade: true).and_return(true)

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([formula_entry], no_upgrade: true, quiet: true)
  end

  it "skips fetching formulae from untapped taps" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "homebrew/foo")
    tapped_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "homebrew/foo/bar")

    allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
      .with("homebrew/foo/bar", no_upgrade: false).and_return(false)

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tap_entry, tapped_formula_entry], quiet: true)
  end

  it "trusts `trusted: true` formulae before fetching them" do
    trusted_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "thirdparty/tap/bar", { trusted: true })

    allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["thirdparty/tap"])

    expect(Homebrew::Trust).to receive(:trust!).with(:formula, "thirdparty/tap/bar").ordered.and_return(true)
    expect(Homebrew::Bundle).to receive(:brew)
      .with("fetch", "thirdparty/tap/bar", verbose: false)
      .ordered
      .and_return(true)

    described_class.install!([trusted_formula_entry], quiet: true)
  end

  it "trusts `trusted: true` casks before fetching them" do
    options = { args: {}, full_name: "thirdparty/tap/baz", trusted: true }
    trusted_cask_entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "baz", options)

    allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return(["thirdparty/tap"])

    expect(Homebrew::Trust).to receive(:trust!).with(:cask, "thirdparty/tap/baz").ordered.and_return(true)
    expect(Homebrew::Bundle).to receive(:brew)
      .with("fetch", "thirdparty/tap/baz", verbose: false)
      .ordered
      .and_return(true)

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

  it "skips fetching formulae from fully qualified untapped taps" do
    tapped_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "homebrew/foo/bar")

    allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
      .with("homebrew/foo/bar", no_upgrade: false).and_return(false)

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tapped_formula_entry], quiet: true)
  end

  it "skips fetching unqualified formulae when Brewfile taps are untapped" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "homebrew/foo")
    untapped_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "bar")

    allow(Homebrew::API).to receive_messages(formula_name?: false, formula_aliases: {}, formula_renames: {})

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tap_entry, untapped_formula_entry], quiet: true)
  end

  it "warns and skips fetching unqualified formulae when API metadata is unavailable" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "homebrew/foo")
    untapped_formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "bar")

    allow(Homebrew::API).to receive(:formula_name?).and_raise("API unavailable")

    expect(described_class).to receive(:opoo).with(/could not check API metadata: API unavailable/)
    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tap_entry, untapped_formula_entry], quiet: true)
  end

  it "prefetches unqualified formulae available without untapped Brewfile taps" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "homebrew/foo")
    formula_entry = Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql")

    allow(Homebrew::API).to receive_messages(formula_name?: true, formula_aliases: {}, formula_renames: {})
    allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?)
      .with("mysql", no_upgrade: false).and_return(false)

    expect(Homebrew::Bundle).to receive(:brew)
      .with("fetch", "mysql", verbose: false)
      .and_return(true)

    described_class.install!([tap_entry, formula_entry], quiet: true)
  end

  it "skips fetching fully qualified casks from untapped taps" do
    tapped_cask_entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "bar", args: {}, full_name: "homebrew/foo/bar")

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tapped_cask_entry], quiet: true)
  end

  it "skips fetching unqualified casks when Brewfile taps are untapped" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "xykong/tap")
    untapped_cask_entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "flux-markdown",
                                                           args: {}, full_name: "flux-markdown")

    allow(Homebrew::API).to receive_messages(cask_token?: false, cask_renames: {})

    expect(Homebrew::Bundle).not_to receive(:brew).with("fetch", any_args)

    described_class.install!([tap_entry, untapped_cask_entry], quiet: true)
  end

  it "prefetches unqualified casks available without untapped Brewfile taps" do
    tap_entry = Homebrew::Bundle::Dsl::Entry.new(:tap, "xykong/tap")
    cask_entry = Homebrew::Bundle::Dsl::Entry.new(:cask, "google-chrome", args: {}, full_name: "google-chrome")

    allow(Homebrew::API).to receive_messages(cask_token?: true, cask_renames: {})
    allow(Homebrew::Bundle::Cask).to receive(:installable_or_upgradable?)
      .with("google-chrome", no_upgrade: false, args: {}, full_name: "google-chrome").and_return(true)

    expect(Homebrew::Bundle).to receive(:brew)
      .with("fetch", "google-chrome", verbose: false)
      .and_return(true)

    described_class.install!([tap_entry, cask_entry], quiet: true)
  end

  describe "parallel installation" do
    let(:alpha_entry) do
      Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "alpha",
        options: {},
        verb:    "Installing",
        cls:     Homebrew::Bundle::Brew,
      )
    end
    let(:beta_entry) do
      Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "beta",
        options: {},
        verb:    "Installing",
        cls:     Homebrew::Bundle::Brew,
      )
    end

    describe "output" do
      subject(:parallel_installer) do
        Homebrew::Bundle::ParallelInstaller.new(
          [],
          jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: false,
        )
      end

      it "uses CRLF for terminal output" do
        output = IO.pipe do |reader, writer|
          allow(writer).to receive(:tty?).and_return(true)

          parallel_installer.send(:write_output, "Installing alpha", stream: writer)
          writer.close

          reader.read
        end

        expect(output).to eq("Installing alpha\r\n")
      end

      it "uses LF for redirected output" do
        output = IO.pipe do |reader, writer|
          allow(writer).to receive(:tty?).and_return(false)

          parallel_installer.send(:write_output, "Installing alpha", stream: writer)
          writer.close

          reader.read
        end

        expect(output).to eq("Installing alpha\n")
      end
    end

    it "installs independent formulae in parallel with jobs > 1" do
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("alpha").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("beta").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("beta").and_return(Set.new)
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("alpha", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)
      expect(Homebrew::Bundle::Brew).to receive(:install!)
        .with("beta", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, beta_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
    end

    it "counts false parallel install results as failures" do
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("alpha").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("beta").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("beta").and_return(Set.new)
      allow(Homebrew::Bundle::Brew).to receive(:install!)
        .with("alpha", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(true)
      allow(Homebrew::Bundle::Brew).to receive(:install!)
        .with("beta", preinstall: true, no_upgrade: false, verbose: false, force: false)
        .and_return(false)

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, beta_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(1)
      expect(failure).to eq(1)
    end

    it "prepares attestation verification before parallel installs" do
      tpack_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "tpack",
        options: { args: {}, full_name: "tmuxpack/tpack/tpack" },
        verb:    "Installing",
        cls:     Homebrew::Bundle::Cask,
      )
      install_order = []

      allow(Homebrew::EnvConfig).to receive(:verify_attestations?).and_return(true)
      allow(Homebrew::Attestation).to receive(:gh_executable) do
        install_order << "gh"
        Pathname("/fake/gh")
      end
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names).with("alpha").and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Cask).to receive(:formula_dependencies).with(["tmuxpack/tpack/tpack"])
                                                                     .and_return([])
      allow(Tap).to receive(:with_cask_token).with("tmuxpack/tpack/tpack").and_return(nil)
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end
      allow(Homebrew::Bundle::Cask).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, tpack_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order.first).to eq("gh")
    end

    it "serializes dependent formulae" do
      install_order = []
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("alpha")
                                                                      .and_return({ dependencies: ["beta"] })
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("beta").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("beta").and_return(Set.new)

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, beta_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["beta", "alpha"])
    end

    it "serializes formulae with shared build-only recursive dependencies" do
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("alpha").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:formulae_by_full_name).with("beta").and_return({ dependencies: [] })
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set["shared-build-dep"])
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("beta").and_return(Set["shared-build-dep"])

      entries = [alpha_entry, beta_entry]
      dependency_map = Homebrew::Bundle::ParallelInstaller.new(
        entries,
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).send(:build_dependency_map, entries)

      expect(dependency_map.fetch("beta")).to eq(Set["alpha"])
    end

    it "installs a Brewfile `gh` before other entries when verifying attestations" do
      gh_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "gh",
        options: {},
        verb:    "Installing",
        cls:     Homebrew::Bundle::Brew,
      )

      allow(Homebrew::EnvConfig).to receive(:verify_attestations?).and_return(true)
      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names).with("gh").and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names).with("alpha").and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("gh").and_return(Set.new)
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)

      entries = [alpha_entry, gh_entry]
      dependency_map = Homebrew::Bundle::ParallelInstaller.new(
        entries,
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).send(:build_dependency_map, entries)

      expect(dependency_map.fetch("alpha")).to eq(Set["gh"])
    end

    it "uses cask full names when resolving formula dependencies" do
      tpack_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "tpack",
        options: { args: {}, full_name: "tmuxpack/tpack/tpack" },
        verb:    "Installing",
        cls:     Homebrew::Bundle::Cask,
      )
      install_order = []

      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names).with("alpha").and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Cask).to receive(:formula_dependencies).with(["tmuxpack/tpack/tpack"])
                                                                     .and_return(["alpha"])
      allow(Tap).to receive(:with_cask_token).with("tmuxpack/tpack/tpack").and_return(nil)
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end
      allow(Homebrew::Bundle::Cask).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, tpack_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["alpha", "tpack"])
    end

    it "taps fully qualified casks before resolving dependencies" do
      tpack_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "tpack",
        options: { args: {}, full_name: "tmuxpack/tpack/tpack" },
        verb:    "Installing",
        cls:     Homebrew::Bundle::Cask,
      )
      install_order = []
      event_order = []
      tap = instance_double(Tap, name: "tmuxpack/tpack", ensure_installed!: nil)

      allow(Homebrew::Bundle::Tap).to receive(:installed_taps).and_return([])
      allow(Tap).to receive(:with_formula_name).with("alpha").and_return(nil)
      allow(Tap).to receive(:with_cask_token).with("tmuxpack/tpack/tpack").and_return([tap, "tpack"])
      allow(tap).to receive(:ensure_installed!) { event_order << :tap_install }
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names).with("alpha").and_return([])
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names).with("alpha").and_return(Set.new)
      allow(Homebrew::Bundle::Cask).to receive(:formula_dependencies).with(["tmuxpack/tpack/tpack"]) do
        event_order << :cask_deps
        ["alpha"]
      end
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end
      allow(Homebrew::Bundle::Cask).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [alpha_entry, tpack_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["alpha", "tpack"])
      expect(event_order).to eq([:tap_install, :cask_deps])
    end

    it "installs unqualified formulae after Brewfile taps" do
      tap_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "homebrew/foo",
        options: {},
        verb:    "Tapping",
        cls:     Homebrew::Bundle::Tap,
      )
      tapped_formula_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "bar",
        options: {},
        verb:    "Installing",
        cls:     Homebrew::Bundle::Brew,
      )
      install_order = []

      allow(Homebrew::API).to receive_messages(formula_name?: false, formula_aliases: {}, formula_renames: {})
      allow(Homebrew::Bundle::Brew).to receive_messages(formula_dep_names: [], recursive_dep_names: Set.new)
      allow(Homebrew::Bundle::Tap).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [tap_entry, tapped_formula_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["homebrew/foo", "bar"])
    end

    it "reads fully qualified formulae after installing their Brewfile taps" do
      tap_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "thirdparty/rootformula",
        options: {},
        verb:    "Tapping",
        cls:     Homebrew::Bundle::Tap,
      )
      tapped_formula_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "thirdparty/rootformula/foo",
        options: {},
        verb:    "Installing",
        cls:     Homebrew::Bundle::Brew,
      )
      install_order = []
      event_order = []

      allow(Homebrew::Bundle::Brew).to receive(:formula_dep_names) do |name|
        event_order << :formula_dep_names
        expect(name).to eq("thirdparty/rootformula/foo")
        []
      end
      allow(Homebrew::Bundle::Brew).to receive(:recursive_dep_names) do |name|
        event_order << :recursive_dep_names
        expect(name).to eq("thirdparty/rootformula/foo")
        Set.new
      end
      allow(Homebrew::Bundle::Tap).to receive(:install!) do |name, **_options|
        install_order << name
        event_order << :tap_install
        true
      end
      allow(Homebrew::Bundle::Brew).to receive(:install!) do |name, **_options|
        install_order << name
        event_order << :formula_install
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [tap_entry, tapped_formula_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["thirdparty/rootformula", "thirdparty/rootformula/foo"])
      expect(event_order).to eq([:tap_install, :formula_dep_names, :recursive_dep_names, :formula_install])
    end

    it "installs unqualified casks after Brewfile taps" do
      tap_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "xykong/tap",
        options: {},
        verb:    "Tapping",
        cls:     Homebrew::Bundle::Tap,
      )
      tapped_cask_entry = Homebrew::Bundle::Installer::InstallableEntry.new(
        name:    "flux-markdown",
        options: { args: {}, full_name: "flux-markdown" },
        verb:    "Installing",
        cls:     Homebrew::Bundle::Cask,
      )
      install_order = []

      allow(Homebrew::API).to receive_messages(cask_token?: false, cask_renames: {})
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(false)
      allow(Homebrew::Bundle::Cask).to receive(:formula_dependencies).with(["flux-markdown"]).and_return([])
      allow(Homebrew::Bundle::Tap).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end
      allow(Homebrew::Bundle::Cask).to receive(:install!) do |name, **_options|
        install_order << name
        true
      end

      success, failure = Homebrew::Bundle::ParallelInstaller.new(
        [tap_entry, tapped_cask_entry],
        jobs: 2, no_upgrade: false, verbose: false, force: false, quiet: true,
      ).run!

      expect(success).to eq(2)
      expect(failure).to eq(0)
      expect(install_order).to eq(["xykong/tap", "flux-markdown"])
    end

    it "falls back to sequential with jobs=1" do
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?).with("mysql",
                                                                                        no_upgrade: false)
                                                                                  .and_return(false)
      allow(Homebrew::Bundle::Brew).to receive(:formula_installed_and_up_to_date?).with("redis",
                                                                                        no_upgrade: false)
                                                                                  .and_return(false)

      expect(Homebrew::Bundle::ParallelInstaller).not_to receive(:new)
      expect(Homebrew::Bundle).to receive(:brew).with("fetch", "mysql", "redis",
                                                      verbose: false).ordered.and_return(true)
      expect(Homebrew::Bundle::Brew).to receive(:preinstall!)
        .with("mysql", no_upgrade: false, verbose: false).ordered.and_return(true)
      expect(Homebrew::Bundle::Brew).to receive(:preinstall!)
        .with("redis", no_upgrade: false, verbose: false).ordered.and_return(true)

      described_class.install!([formula_entry, second_formula_entry], jobs: 1, quiet: true)
    end
  end
end
