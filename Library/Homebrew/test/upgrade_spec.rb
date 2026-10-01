# typed: strict
# frozen_string_literal: true

require "upgrade"
require "install"
require "formula_installer"
require "dependency"
require "keg"
require "pkg_version"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::Upgrade do
  describe "::format_upgrade_summary" do
    it "aligns a large mixed list of package names and versions" do
      upgrades = [
        "sqlite 3.53.1 -> 3.53.2 (2.4MB)",
        "docker 29.5.2 -> 29.6.0 (9.3MB)",
        "gh 2.93.0 -> 2.95.0 (13.4MB)",
        "python@3.14 3.14.5 -> 3.14.6 (19.2MB)",
        "pnpm 11.5.1 -> 11.8.0 (4MB)",
        "usage 3.4.0 -> 3.5.2 (2.9MB)",
        "certifi 2026.5.20 -> 2026.6.17 (5.7KB)",
        "libvmaf 3.1.0 -> 3.2.0 (1.2MB)",
        "kubernetes-cli 1.36.1 -> 1.36.2 (18.2MB)",
        "jq 1.8.1 -> 1.8.2 (441KB)",
        "mise 2026.6.0 -> 2026.6.11 (34.8MB)",
        "sdl2 2.32.70 (636.8KB)",
        "opencode-desktop 1.14.48 -> 1.17.9",
        "slack 4.48.102 -> 4.50.140",
        "spotify 1.2.84.476 -> 1.2.92.148",
        "visual-studio-code 1.111.0 -> 1.125.1",
      ]

      expect(described_class.format_upgrade_summary(upgrades)).to eq([
        "sqlite              3.53.1     -> 3.53.2 (2.4MB)",
        "docker              29.5.2     -> 29.6.0 (9.3MB)",
        "gh                  2.93.0     -> 2.95.0 (13.4MB)",
        "python@3.14         3.14.5     -> 3.14.6 (19.2MB)",
        "pnpm                11.5.1     -> 11.8.0 (4MB)",
        "usage               3.4.0      -> 3.5.2 (2.9MB)",
        "certifi             2026.5.20  -> 2026.6.17 (5.7KB)",
        "libvmaf             3.1.0      -> 3.2.0 (1.2MB)",
        "kubernetes-cli      1.36.1     -> 1.36.2 (18.2MB)",
        "jq                  1.8.1      -> 1.8.2 (441KB)",
        "mise                2026.6.0   -> 2026.6.11 (34.8MB)",
        "sdl2                2.32.70 (636.8KB)",
        "opencode-desktop    1.14.48    -> 1.17.9",
        "slack               4.48.102   -> 4.50.140",
        "spotify             1.2.84.476 -> 1.2.92.148",
        "visual-studio-code  1.111.0    -> 1.125.1",
      ])
    end
  end

  describe "::upgrade_formula" do
    it "shows the version transition for an unlinked dependency installed at an older version" do
      python = formula("python@3.14") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/python-3.14.6.tgz"
      end
      ["2.7.14_2", "3.6.1", "3.6.4_4", "3.7.1"].each do |version|
        (python.rack/version).mkpath
        tab = Tab.empty
        tab.tabfile = python.rack/version/AbstractTab::FILENAME
        tab.write
      end
      dependency = instance_double(Dependency, to_formula: python)
      formula_installer = instance_double(
        FormulaInstaller, formula: Testball.new, compute_dependencies: [dependency]
      )

      expect { described_class.upgrade_formula(formula_installer, dry_run: true) }
        .to output(/Would upgrade.*python@3.14 3.7.1 -> 3.14.6/m).to_stdout
    end

    it "reports a failed upgrade instead of aborting the rest of the batch" do
      formula_installer = instance_double(FormulaInstaller, formula: Testball.new)
      allow(Homebrew::Install).to receive(:install_formula).and_raise("gzip decompression failed")

      expect do
        expect(described_class.upgrade_formula(formula_installer)).to be(false)
      end.to output(/Error: testball: gzip decompression failed/).to_stderr
    end
  end

  describe "::upgrade_formulae" do
    it "can defer cleanup until the batch has finished installing" do
      formula_installer = instance_double(FormulaInstaller, formula: Testball.new)

      allow(described_class).to receive(:upgrade_formula).with(
        formula_installer,
        dry_run:            false,
        verbose:            false,
        skip_formula_names: [],
        dependency_summary: nil,
      ).and_return(true)
      expect(Homebrew::Cleanup).not_to receive(:install_formula_clean!)

      expect(described_class.upgrade_formulae([formula_installer], fetch: false, cleanup: false))
        .to eq([formula_installer])
    end

    it "groups dependencies across formula upgrades" do
      fresh = formula("fresh-dependency") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/fresh-dependency-2.0"
      end
      installed = formula("installed-dependency") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/installed-dependency-2.0"
      end
      allow(fresh).to receive_messages(any_version_installed?: false, optlinked?: false, installed_kegs: [])
      (installed.rack/"1.0").mkpath
      tab = Tab.empty
      tab.tabfile = installed.rack/"1.0"/AbstractTab::FILENAME
      tab.write
      Keg.new(installed.rack/"1.0").optlink
      fresh_dependency = instance_double(Dependency, to_formula: fresh)
      installed_dependency = instance_double(Dependency, to_formula: installed)
      formula_installers = [
        instance_double(FormulaInstaller, formula:              Testball.new,
                                          compute_dependencies: [fresh_dependency, installed_dependency]),
        instance_double(FormulaInstaller, formula: Testball.new, compute_dependencies: [installed_dependency]),
      ]
      allow(Homebrew::Cleanup).to receive(:install_cleanup_formulae).and_return([])

      expect do
        described_class.upgrade_formulae(formula_installers, dry_run: true)
      end.to output(<<~EOS).to_stdout
        ==> Would install 1 dependency:
        fresh-dependency 2.0
        ==> Would upgrade 1 dependency:
        installed-dependency 1.0 -> 2.0
      EOS
    end
  end

  describe "::formula_installers" do
    it "explains when installed dependencies satisfy the bottle metadata" do
      dependent = formula("dependent") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependent-2.0"
      end
      formula_installer = instance_double(
        FormulaInstaller,
        bottle_tab_runtime_dependencies: { "dependency" => { "version" => "2.0", "revision" => "0" } },
        determine_bottle_tab_attributes: nil,
        fetch_bottle_tab:                nil,
        formula:                         dependent,
      )
      dependency = instance_double(Dependency)
      download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)

      allow(Migrator).to receive(:migrate_if_needed)
      allow(described_class).to receive(:create_formula_installer).and_return(formula_installer)
      allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
      allow(Dependency).to receive(:new).with("dependency").and_return(dependency)
      allow(dependency).to receive(:installed?)
        .with(minimum_version: Version.new("2.0"), minimum_revision: 0)
        .and_return(true)

      expect do
        described_class.formula_installers([dependent], flags: [], dependents: true)
      end.to output(
        "==> Not upgrading dependent: installed runtime dependencies satisfy bottle metadata\n",
      ).to_stdout
    end

    it "keeps the requested order within keg-only and non-keg-only formulae" do
      names = %w[a b c d e f g h i j]
      formulae = names.map do |name|
        formula(name) do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/#{name}-1.0"
          keg_only "to test keg only formulae ordered first without further order mutation" if %w[c h].include?(name)
        end
      end
      download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)

      allow(Migrator).to receive(:migrate_if_needed)
      allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
      allow(described_class).to receive(:create_formula_installer) do |formula|
        instance_double(FormulaInstaller, determine_bottle_tab_attributes: nil, fetch_bottle_tab: nil, formula:)
      end

      installers = described_class.formula_installers(formulae, flags: [])
      expect(installers.map { |installer| installer.formula.name }).to eq(%w[c h a b d e f g i j])
    end
  end

  describe "::dependent_formula_installers" do
    it "excludes primary formulae without a caveat mode option" do
      primary = Testball.new
      dependant = formula("dependant") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependant-2.0"
      end
      formula_installer = FormulaInstaller.new(dependant)
      dependants = Homebrew::Upgrade::Dependents.new(
        upgradeable: [primary, dependant], pinned: [], skipped: [],
      )

      expect(described_class).to receive(:formula_installers) do |formulae, **options|
        expect(formulae).to eq([dependant])
        expect(options).to include(flags: [], dependents: true)
        expect(options).not_to have_key(:defer_caveats)
        [formula_installer]
      end

      expect(described_class.dependent_formula_installers(
               dependants,
               [primary],
               flags: [],
             )).to eq([formula_installer])
    end
  end

  describe "::upgrade_dependents" do
    it "returns installed dependents unless they are primary formulae" do
      installed_dependent = formula("installed-dependent") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/installed-dependent-2.0"
      end
      primary_formula = formula("primary") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/primary-2.0"
      end
      FormulaInstaller.installed.merge([installed_dependent, primary_formula])
      dependants = Homebrew::Upgrade::Dependents.new(
        upgradeable: [installed_dependent, primary_formula], pinned: [], skipped: [],
      )

      expect(described_class.upgrade_dependents(dependants, [primary_formula], flags: []))
        .to contain_exactly(installed_dependent)
    end

    it "installs prefetched dependants without fetching again" do
      dependant = formula("dependant") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependant-2.0"
      end
      formula_installer = FormulaInstaller.new(dependant)
      dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [dependant], pinned: [], skipped: [])

      allow(FormulaInstaller).to receive(:installed).and_return(Set.new)
      expect(described_class).not_to receive(:formula_installers)
      expect(described_class).to receive(:filter_dependent_formula_installers)
        .with([formula_installer])
        .and_return([formula_installer])
      expect(described_class).to receive(:upgrade_formulae)
        .with([formula_installer], verbose: false, cleanup: false, fetch: false)
        .and_return([formula_installer])

      expect(described_class.upgrade_dependents(
               dependants,
               [],
               flags:                         [],
               cleanup:                       false,
               prefetched_formula_installers: [formula_installer],
             )).to eq([dependant])
    end

    it "rechecks prefetched dependants after primary formulae are installed" do
      dependant = Testball.new
      formula_installer = FormulaInstaller.new(dependant)
      dependants = Homebrew::Upgrade::Dependents.new(upgradeable: [dependant], pinned: [], skipped: [])

      allow(FormulaInstaller).to receive(:installed).and_return(Set.new)
      expect(described_class).to receive(:filter_dependent_formula_installers)
        .with([formula_installer])
        .and_return([])
      expect(described_class).not_to receive(:upgrade_formulae)

      expect(described_class.upgrade_dependents(
               dependants,
               [],
               flags:                         [],
               prefetched_formula_installers: [formula_installer],
             )).to be_empty
    end
  end
end
