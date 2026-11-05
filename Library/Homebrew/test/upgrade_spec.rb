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
    context "with a dependent built against a dependency kept by minimum_version" do
      # Keep each Sorbet signature with its let declaration.
      # rubocop:disable RSpec/ScatteredLet
      sig { returns(Formula) }
      let(:upgraded) do
        formula("kept-dependency") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/kept-dependency-2.0"
        end
      end

      sig { returns(Formula) }
      let(:dependent) do
        formula("kept-dependent") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/kept-dependent-2.0"
        end
      end

      sig { returns(Homebrew::Upgrade::Dependents) }
      let(:dependants) { Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: []) }

      sig { returns(T::Boolean) }
      let(:poured_from_bottle) { false }
      # rubocop:enable RSpec/ScatteredLet

      before do
        allow(dependent).to receive(:any_installed_keg).and_return(
          instance_double(Keg,
                          tab:                  instance_double(Tab, poured_from_bottle:),
                          runtime_dependencies: [{ "full_name"                  => upgraded.full_name,
                                                   "kept_compatibility_version" => 1 }]),
        )
        allow(upgraded).to receive(:runtime_installed_formula_dependents).and_return([dependent])
        ENV["HOMEBREW_NO_ENV_HINTS"] = "1"
      end

      it "plans to rebuild it when the dependency is upgraded for a requested formula" do
        stub_formula_loader(upgraded)
        requested_installer = instance_double(FormulaInstaller, formula: formula("requested") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/requested-2.0"
        end, ignore_deps?: false, compute_dependencies: [Dependency.new(upgraded.name)])

        expect do
          described_class.upgrade_dependents(dependants, [], flags: [], dry_run: true,
                                             upgrading_formula_installers: [requested_installer])
        end.to output(<<~EOS).to_stdout
          ==> Would rebuild 1 dependent against upgraded dependencies:
          kept-dependent 2.0
        EOS
      end

      it "plans to upgrade it in one build when it's outdated" do
        allow(dependent).to receive(:outdated?).and_return(true)
        allow(described_class).to receive(:installed_version).with(dependent)
                                                             .and_return(PkgVersion.new(Version.new("1.0"), 0))

        expect { described_class.upgrade_dependents(dependants, [upgraded], flags: [], dry_run: true) }
          .to output(<<~EOS).to_stdout
            ==> Would rebuild 1 dependent against upgraded dependencies:
            kept-dependent 1.0 -> 2.0
          EOS
      end

      context "when the dependency was upgraded in this run" do
        sig { returns(Homebrew::Reinstall::InstallationContext) }
        let(:reinstall_context) do
          instance_double(Homebrew::Reinstall::InstallationContext,
                          formula: dependent, formula_installer: FormulaInstaller.new(dependent))
        end

        before do
          FormulaInstaller.installed << upgraded
          allow(Homebrew::Reinstall).to receive(:build_install_context).and_return(reinstall_context)
          allow(Homebrew::Reinstall).to receive(:reinstall_formula)
          allow(Homebrew::Install).to receive(:fetch_formulae).and_return([reinstall_context.formula_installer])
        end

        it "prints that it's rebuilding it" do
          expect { described_class.upgrade_dependents(dependants, [], flags: []) }
            .to output(<<~EOS).to_stdout
              ==> Checking for dependents of upgraded formulae...
              ==> Rebuilding 1 dependent against upgraded dependencies:
              kept-dependent 2.0
            EOS
        end

        it "rebuilds it from source" do
          expect(Homebrew::Reinstall).to receive(:build_install_context)
            .with(dependent, hash_including(build_from_source_formulae: [dependent.full_name]))
            .and_return(reinstall_context)

          described_class.upgrade_dependents(dependants, [], flags: [])
        end

        it "rebuilds it when it's outdated" do
          allow(dependent).to receive(:outdated?).and_return(true)
          expect(Homebrew::Reinstall).to receive(:reinstall_formula).with(reinstall_context)

          described_class.upgrade_dependents(dependants, [], flags: [])
        end

        it "warns instead of rebuilding it when it's pinned" do
          allow(dependent).to receive(:pinned?).and_return(true)

          expect { described_class.upgrade_dependents(dependants, [], flags: []) }
            .to output(<<~EOS).to_stderr
              Warning: Not rebuilding 1 pinned dependent against upgraded dependencies:
              kept-dependent 2.0
            EOS
        end

        it "doesn't rebuild it when it's pinned" do
          allow(dependent).to receive(:pinned?).and_return(true)
          expect(Homebrew::Reinstall).not_to receive(:reinstall_formula)

          described_class.upgrade_dependents(dependants, [], flags: [])
        end
      end

      it "doesn't reinstall it if it was rebuilt in this run" do
        FormulaInstaller.installed.merge([upgraded, dependent])
        expect(Homebrew::Reinstall).not_to receive(:build_install_context)

        described_class.upgrade_dependents(dependants, [], flags: [])
      end

      it "doesn't reinstall it if it was upgraded as an outdated dependent in this run" do
        FormulaInstaller.installed << upgraded
        formula_installer = FormulaInstaller.new(dependent)
        allow(described_class).to receive(:formula_installers).and_return([formula_installer])
        allow(described_class).to receive(:upgrade_formulae) do
          FormulaInstaller.installed << dependent
          [formula_installer]
        end
        expect(Homebrew::Reinstall).not_to receive(:build_install_context)

        described_class.upgrade_dependents(
          Homebrew::Upgrade::Dependents.new(upgradeable: [dependent], pinned: [], skipped: []), [], flags: []
        )
      end

      it "doesn't plan to rebuild it with HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK" do
        ENV["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"

        expect { described_class.upgrade_dependents(dependants, [upgraded], flags: [], dry_run: true) }
          .not_to output.to_stdout
      end

      it "doesn't plan to rebuild it if the upgraded dependency wasn't kept" do
        allow(dependent).to receive(:any_installed_keg).and_return(
          instance_double(Keg, tab:                  instance_double(Tab, poured_from_bottle:),
                               runtime_dependencies: [{ "full_name" => upgraded.full_name }]),
        )

        expect { described_class.upgrade_dependents(dependants, [upgraded], flags: [], dry_run: true) }
          .not_to output.to_stdout
      end

      context "when it was poured from a bottle" do
        sig { returns(T::Boolean) }
        let(:poured_from_bottle) { true }

        it "doesn't plan to rebuild it" do
          expect { described_class.upgrade_dependents(dependants, [upgraded], flags: [], dry_run: true) }
            .not_to output.to_stdout
        end
      end
    end

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
