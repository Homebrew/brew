# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"
require "cmd/shared_examples/reinstall_pkgconf_if_needed"

RSpec.describe Homebrew::Cmd::UpgradeCmd do
  include FileUtils

  it_behaves_like "parseable arguments"

  it "upgrades a Formula", :integration_test do
    formula_name = "testball_bottle"
    formula_rack = HOMEBREW_CELLAR/formula_name

    setup_test_formula formula_name

    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(formula_rack/"0.1").to be_a_directory
    expect(formula_rack/"0.0.1").not_to exist

    uninstall_test_formula formula_name

    # links newer version when upgrade was interrupted
    (formula_rack/"0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(formula_rack/"0.1").to be_a_directory
    expect(HOMEBREW_PREFIX/"opt/#{formula_name}").to be_a_symlink
    expect(HOMEBREW_PREFIX/"var/homebrew/linked/#{formula_name}").to be_a_symlink

    uninstall_test_formula formula_name

    # upgrades with asking for user prompts
    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade", "--ask" }
      .to output(/.*Formula\s*\(1\):\s*#{formula_name}.*/).to_stdout
      .and output(/✔︎.*/m).to_stderr

    expect(formula_rack/"0.1").to be_a_directory
    expect(formula_rack/"0.0.1").not_to exist

    uninstall_test_formula formula_name

    # refuses to upgrade a forbidden formula
    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
      .to not_to_output(%r{#{formula_rack}/0\.1}o).to_stdout
      .and output(/#{formula_name} was forbidden/).to_stderr
      .and be_a_failure
    expect(formula_rack/"0.1").not_to exist
  end

  it "reports unavailable names via ofail and continues upgrading" do
    error = FormulaOrCaskUnavailableError.new("nonexistent")
    formula = instance_double(Formula, full_name: "testball")

    cmd = described_class.new(["testball", "nonexistent"])
    allow(cmd.args.named).to receive(:present?).and_return(true)
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable)
      .with(method: :resolve)
      .and_return([formula, error])

    allow(cmd).to receive_messages(upgrade_outdated_formulae!: true, upgrade_outdated_casks!: false)

    expect { cmd.run }
      .to output(/nonexistent/).to_stderr

    expect(Homebrew).to have_failed
  end

  it "catches cask upgrade errors and sets Homebrew.failed" do
    allow(Cask::Upgrade).to receive(:upgrade_casks!).and_raise(Cask::CaskError.new("test cask error"))

    cmd = described_class.new(["--cask"])
    expect { cmd.send(:upgrade_outdated_casks!, []) }
      .to output(/test cask error/).to_stderr

    expect(Homebrew).to have_failed
  end

  it "prints a combined upgrade summary before fetching combined downloads" do
    cmd = described_class.new([])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
    cask = instance_double(
      Cask::Cask,
      artifacts:         [],
      full_name:         "codex",
      installed_version: "0.117.0",
      version:           "0.118.0",
    )
    installer = instance_double(Cask::Installer, prelude: nil, enqueue_downloads: nil)

    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(cmd).to receive(:upgrade_outdated_formulae!) do |_, prefetch_only: false,
                                                              prefetch_names: nil,
                                                              prefetch_upgrades: nil,
                                                              show_upgrade_summary: true,
                                                              **|
      if prefetch_only
        expect(show_upgrade_summary).to be(false)
        prefetch_names&.replace(["deno"])
        prefetch_upgrades&.replace(["deno 2.7.10 -> 2.7.11"])
      end

      true
    end
    allow(Cask::Upgrade).to receive(:outdated_casks).and_return([cask])
    allow(Cask::Installer).to receive(:new).and_return(installer)
    allow(Cask::Upgrade).to receive(:upgrade_casks!) do |*_, **kwargs|
      expect(kwargs[:skip_prefetch]).to be(true)
      expect(kwargs[:show_upgrade_summary]).to be(false)

      true
    end
    allow(Homebrew::Cleanup).to receive(:periodic_clean!)
    allow(Homebrew::Reinstall).to receive(:reinstall_pkgconf_if_needed!)
    allow(Homebrew.messages).to receive(:display_messages)

    expect { cmd.run }.to output(<<~EOS).to_stdout
      ==> Upgrading 2 outdated packages:
      deno 2.7.10 -> 2.7.11
      codex 0.117.0 -> 0.118.0
      ==> Fetching downloads for: deno and codex
    EOS
  end

  it "does not print removed caveats method errors for installed casks", :cask do
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    installer = InstallHelper.install_with_caskfile(cask)
    installed_caskfile = installer.metadata_subdir/"#{cask.token}.rb"
    expect(installed_caskfile).to exist

    installed_caskfile.write(
      installed_caskfile.read.sub(
        /\nend\n\z/,
        <<~RUBY,
            caveats do
              discontinued
            end
          end
        RUBY
      ),
    )

    (CoreCaskTap.instance.cask_dir/"local-caffeine.rb").unlink
    CoreCaskTap.instance.clear_cache

    cmd = described_class.new(["--cask", "--dry-run"])

    expect { cmd.send(:upgrade_outdated_casks!, []) }
      .to not_to_output(/Unexpected method 'discontinued' called during caveats on Cask local-caffeine\./).to_stderr
  end

  it_behaves_like "reinstall_pkgconf_if_needed"
end
