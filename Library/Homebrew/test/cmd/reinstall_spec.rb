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

  it "asks for casks before shared prefetch when reinstalling formulae and casks" do
    cmd = described_class.new(["testball", "local-caffeine"])
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    formula_installer = FormulaInstaller.new(formula)
    dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: [])
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
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
    allow(Homebrew::Upgrade).to receive(:dependants).and_return(dependants)
    allow(Homebrew::Install).to receive(:ask_formulae)
    allow(Homebrew::Install).to receive(:show_combined_fetch_downloads_heading)
    allow(Homebrew::Install).to receive(:enqueue_formulae).and_return([formula_installer])
    allow(Homebrew::Install).to receive(:enqueue_cask_installers)
    allow(Cask::Installer).to receive(:new).and_return(instance_double(Cask::Installer))
    allow(Homebrew::Reinstall).to receive(:reinstall_formula)
    allow(Homebrew::Upgrade).to receive(:upgrade_dependents)
    allow(Cask::Reinstall).to receive(:reinstall_casks)
    allow(Homebrew::Cleanup).to receive(:periodic_clean!)
    allow(Homebrew.messages).to receive(:display_messages)

    expect(Homebrew::Install).to receive(:ask_casks)
      .with([cask], action: "reinstallation", skip_cask_deps: false)
      .ordered
    expect(Homebrew::DownloadQueue).to receive(:new).ordered.and_return(download_queue)

    cmd.run
  end

  it "starts formula prelude fetches before dependant checks when not asking" do
    cmd = described_class.new(["--yes", "testball"])
    download_queue = instance_double(Homebrew::DownloadQueue, shutdown: nil)
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-0.1.tar.gz"
    end
    formula_installer = FormulaInstaller.new(formula)
    dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: [])
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
    allow(Homebrew::Reinstall).to receive(:reinstall_formula)
    allow(Homebrew::Upgrade).to receive(:upgrade_dependents)
    allow(Homebrew::Cleanup).to receive(:periodic_clean!)
    allow(Homebrew.messages).to receive(:display_messages)
    expect(Homebrew::DownloadQueue).to receive(:new).ordered.and_return(download_queue)
    expect(formula_installer).to receive(:download_queue=).with(download_queue).ordered
    expect(formula_installer).to receive(:prelude_fetch).ordered
    expect(Homebrew::Upgrade).to receive(:dependants).ordered.and_return(dependants)
    expect(Homebrew::Install).to receive(:fetch_formulae)
      .with([formula_installer], download_queue:, shutdown_download_queue: false)
      .ordered
      .and_return([formula_installer])
    expect(download_queue).to receive(:shutdown).ordered

    cmd.run
  end

  it "reinstalls a Formula", :aggregate_failures, :integration_test do
    formula_name = "testball_bottle"
    formula_prefix = HOMEBREW_CELLAR/formula_name/"0.1"
    formula_bin = formula_prefix/"bin"

    setup_test_formula formula_name, tab_attributes: { installed_on_request: true }
    Keg.new(formula_prefix).link

    expect(formula_bin).not_to exist

    expect { brew "reinstall", formula_name }
      .to output(/Reinstalling #{formula_name}/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(formula_bin).to exist

    FileUtils.rm_r(formula_bin)

    expect { brew "reinstall", formula_name }
      .to output(/.*Would reinstall 1 formula:\s*#{formula_name}.*/).to_stdout
      .and output(/✔︎.*/m).to_stderr
      .and be_a_success
    expect(formula_bin).to exist

    FileUtils.rm_r(formula_bin)

    expect { brew "reinstall", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
      .to not_to_output(/#{Regexp.escape(formula_prefix)}/o).to_stdout
      .and output(/#{formula_name} was forbidden/).to_stderr
      .and be_a_failure
    expect(formula_bin).not_to exist
  end
end
