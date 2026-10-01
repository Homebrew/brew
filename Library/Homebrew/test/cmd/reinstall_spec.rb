# typed: strict
# frozen_string_literal: true

require "extend/ENV"
require "cmd/reinstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Reinstall do
  it_behaves_like "parseable arguments"

  it "reports unavailable names via ofail and continues reinstalling" do
    error = FormulaOrCaskUnavailableError.new("nonexistent")
    formula = instance_double(Formula, full_name: "testball", pinned?: false)
    allow(formula).to receive(:latest_formula).and_return(formula)

    cmd = described_class.new(["testball", "nonexistent"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([formula, error])
    expect(Homebrew::Trust).to receive(:trust_fully_qualified_items!)
      .with(["testball", "nonexistent"], type: nil)

    expect { cmd.run }
      .to output(/nonexistent/).to_stderr

    expect(Homebrew).to have_failed
  end

  it "does not reinstall a pinned Cask" do
    cask = Cask::Cask.new("local-caffeine")
    allow(cask).to receive_messages(pinned?: true, full_name: "local-caffeine")

    cmd = described_class.new(["local-caffeine"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([cask])
    allow(Homebrew::Cleanup).to receive(:periodic_clean!)
    allow(Homebrew.messages).to receive(:display_messages)

    expect(Cask::Reinstall).not_to receive(:reinstall_casks)
    expect { cmd.run }
      .to output(/local-caffeine is pinned\. You must unpin it to reinstall\./).to_stderr
  end

  it "cleans a reinstalled cask before displaying deferred caveats" do
    cask = Cask::Cask.new("local-caffeine")
    allow(cask).to receive(:pinned?).and_return(false)
    cmd = described_class.new(["--yes", "local-caffeine"])

    allow(Homebrew::Trust).to receive(:trust_fully_qualified_items!)
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([cask])
    expect(Cask::Reinstall).to receive(:reinstall_casks)
      .with(
        cask,
        binaries:        true,
        verbose:         false,
        force:           false,
        require_sha:     false,
        skip_cask_deps:  false,
        zap:             false,
        skip_prefetch:   false,
        download_queue:  nil,
        cask_installers: nil,
      )
      .ordered
      .and_return([cask])
    expect(Homebrew::Cleanup).to receive(:install_clean!)
      .with(formulae: [], casks: [cask])
      .ordered
    expect(Homebrew::Cleanup).to receive(:periodic_clean!).ordered
    expect(Homebrew.messages).to receive(:display_messages)
      .with(force_caveats: true, display_times: false)
      .ordered

    cmd.run
  end

  it "asks for casks before shared prefetch when reinstalling formulae and casks" do
    cmd = described_class.new(["testball", "local-caffeine"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    formula_installer = FormulaInstaller.new(formula)
    dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: [])
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    cask_installer = instance_double(Cask::Installer)
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil, failed_downloads: [])
    reinstall_context = Homebrew::Reinstall::InstallationContext.new(
      formula_installer:,
      formula:,
      keg:               nil,
      options:           Options.create([]),
    )

    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([formula, cask])
    allow(formula).to receive(:latest_formula).and_return(formula)
    allow(Migrator).to receive(:migrate_if_needed)
    allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
    allow(Homebrew::Reinstall).to receive(:build_install_context).and_return(reinstall_context)
    allow(Homebrew::Install).to receive(:ask_formulae)
    allow(Homebrew::Install).to receive_messages(enqueue_formulae:        [formula_installer],
                                                 enqueue_cask_installers: [cask_installer])
    allow(Homebrew::Install).to receive(:fetch_cask_dependencies)
    allow(Cask::Installer).to receive(:new).and_return(cask_installer)
    allow(Homebrew::Reinstall).to receive(:reinstall_formula)
    allow(Homebrew::Upgrade).to receive_messages(dependants: dependants, upgrade_dependents: [])
    expect(Cask::Reinstall).to receive(:reinstall_casks) do |reinstalled_cask, cask_installers:, **|
      expect([reinstalled_cask, cask_installers]).to eq([cask, [cask_installer]])
      [cask]
    end
    allow(Homebrew::Cleanup).to receive_messages(install_clean!: nil, periodic_clean!: nil)
    allow(Homebrew.messages).to receive(:display_messages)

    expect(Homebrew::Install).to receive(:ask_casks)
      .with([cask], action: "reinstallation", skip_cask_deps: false)
      .ordered
    expect(Homebrew::DownloadQueue).to receive(:new).ordered.and_return(download_queue)
    expect(download_queue).to receive(:fetch)
      .with(heading: "Fetching downloads for: testball and local-caffeine")
      .ordered

    cmd.run
  end

  it "starts formula prelude fetches before dependant checks when not asking" do
    cmd = described_class.new(["--yes", "testball"])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil, failed_downloads: [])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    formula_installer = FormulaInstaller.new(formula)
    dependant = formula("dependant") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/dependant-0.1.tar.gz"
    end
    dependant_installer = FormulaInstaller.new(dependant)
    dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [dependant], pinned: [], skipped: [])
    reinstall_context = Homebrew::Reinstall::InstallationContext.new(
      formula_installer:,
      formula:,
      keg:               nil,
      options:           Options.create([]),
    )

    allow(Homebrew::Trust).to receive(:trust_fully_qualified_items!)
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([formula])
    allow(formula).to receive_messages(latest_formula: formula, pinned?: false)
    allow(Migrator).to receive(:migrate_if_needed)
    allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
    allow(Homebrew::Reinstall).to receive(:build_install_context).and_return(reinstall_context)
    expect(Homebrew::DownloadQueue).to receive(:new).ordered.and_return(download_queue)
    expect(formula_installer).to receive(:download_queue=).with(download_queue).ordered
    expect(formula_installer).to receive(:prelude_fetch).ordered
    expect(Homebrew::Upgrade).to receive(:dependants).ordered.and_return(dependants)
    expect(Homebrew::Upgrade).to receive(:dependent_formula_installers)
      .ordered
      .and_return([dependant_installer])
    expect(Homebrew::Install).to receive(:enqueue_formulae)
      .with([formula_installer, dependant_installer], download_queue:)
      .ordered
      .and_return([formula_installer, dependant_installer])
    expect(download_queue).to receive(:fetch).ordered
    expect(download_queue).to receive(:shutdown).ordered
    expect(Homebrew::Reinstall).to receive(:reinstall_formula).with(reinstall_context).ordered
    expect(Homebrew::Upgrade).to receive(:upgrade_dependents) do |actual_dependants, _, **options|
      expect(actual_dependants).to eq(dependants)
      expect(options).to include(
        cleanup:                       false,
        prefetched_formula_installers: [dependant_installer],
      )
      [dependant]
    end.ordered
    expect(Homebrew::Cleanup).to receive(:install_clean!)
      .with(formulae: [formula, dependant], casks: [])
      .ordered
    expect(Homebrew::Cleanup).to receive(:periodic_clean!).ordered
    expect(Homebrew.messages).to receive(:display_messages)
      .with(force_caveats: true, display_times: false)
      .ordered

    cmd.run
  end

  it "reinstalls the remaining formulae after one fails" do
    cmd = described_class.new(["--yes", "one", "two"])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil, failed_downloads: [])
    dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: [])
    contexts = %w[one two].map do |name|
      formula = formula(name) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/#{name}-0.1.tar.gz"
      end
      allow(formula).to receive_messages(latest_formula: formula, pinned?: false)
      Homebrew::Reinstall::InstallationContext.new(
        formula_installer: FormulaInstaller.new(formula),
        formula:,
        keg:               nil,
        options:           Options.create([]),
      )
    end

    allow(Homebrew::Trust).to receive(:trust_fully_qualified_items!)
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return(contexts.map(&:formula))
    allow(Migrator).to receive(:migrate_if_needed)
    allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(Homebrew::Reinstall).to receive(:build_install_context).and_return(*contexts)
    allow(Homebrew::Install).to receive(:enqueue_formulae).and_return(contexts.map(&:formula_installer))
    allow(Homebrew::Reinstall).to receive(:reinstall_formula).with(contexts.fetch(0))
                                                             .and_raise("gzip decompression failed")
    allow(Homebrew::Cleanup).to receive_messages(install_clean!: nil, periodic_clean!: nil)
    allow(Homebrew::Upgrade).to receive_messages(dependants:, upgrade_dependents: [])
    allow(Homebrew.messages).to receive(:display_messages)

    expect(Homebrew::Reinstall).to receive(:reinstall_formula).with(contexts.fetch(1))

    expect { cmd.run }.to output(/Error: one: gzip decompression failed/).to_stderr
  end

  it "reinstalls a Formula and Cask", :cask, :integration_test do
    formula_name = "testball_bottle"
    formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
    formula_bin = formula_prefix/"bin"

    setup_test_formula formula_name, tab_attributes: { installed_on_request: true }
    Keg.new(formula_prefix).link

    expect(formula_bin).not_to exist
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    InstallHelper.stub_cask_installation(cask)

    expect do
      brew "reinstall", "--no-ask", "--appdir=#{Cask::Config::DEFAULT_DIRS_PATHNAMES[:appdir]}", formula_name,
           cask_path("local-caffeine"), "HOMEBREW_TEST_GENERIC_OS" => "1"
    end
      .to output(/Reinstalling #{formula_name}/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(formula_bin).to exist
  end
end
