# typed: strict
# frozen_string_literal: true

require "cask/installer"
require "install"
require "dependency"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::Install do
  specify "::perform_preinstall_checks runs non-fatal preinstall diagnostics" do
    allow(described_class).to receive(:check_prefix)
    allow(described_class).to receive(:check_cpu)
    allow(described_class).to receive(:attempt_directory_creation)

    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:supported_configuration_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:preinstall_checks, fatal: false)
      .ordered
    expect(Homebrew::Diagnostic).to receive(:checks)
      .with(:fatal_preinstall_checks)
      .ordered

    described_class.perform_preinstall_checks
  end

  specify "::check_prefix enforces macOS prefixes only on macOS" do
    stub_const("HOMEBREW_PREFIX", Pathname("/opt/homebrew"))
    stub_const("HOMEBREW_MACOS_ARM_DEFAULT_PREFIX", "/opt/homebrew")
    allow(Hardware::CPU).to receive_messages(intel?: true, in_rosetta2?: false)

    if OS.mac?
      expect { described_class.check_prefix }.to raise_error(SystemExit)
    else
      expect { described_class.check_prefix }.not_to raise_error
    end
  end

  describe "::fetch_formulae" do
    it "skips formulae whose fetch steps raise and continues with the rest" do
      good_fi = FormulaInstaller.new(formula("good-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      bad_fi = FormulaInstaller.new(formula("bad-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      [good_fi, bad_fi].each do |fi|
        allow(fi).to receive(:prelude_fetch)
        allow(fi).to receive(:prelude)
      end
      allow(good_fi).to receive(:enqueue_fetch)
      allow(bad_fi).to receive(:enqueue_fetch).and_raise("unexpected failure")

      expect do
        expect(described_class.fetch_formulae([good_fi, bad_fi])).to eq([good_fi])
      end.to output(/Error: bad-bottle: unexpected failure/).to_stderr
    end
  end

  describe "::reject_failed_downloads" do
    it "skips the formula whose download failed, keeps the rest and unmarks the failure as fetched" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      bad_formula = formula("bad-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      good_formula = formula("good-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      failed_bottle = Bottle.new(bad_formula, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur))
      bad_fi = instance_double(FormulaInstaller, formula: bad_formula)
      good_fi = instance_double(FormulaInstaller, formula: good_formula)
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [failed_bottle])
      FormulaInstaller.fetched.merge([bad_formula, good_formula])

      expect(described_class.reject_failed_downloads([bad_fi, good_fi], download_queue:)).to eq([good_fi])
      expect(FormulaInstaller.fetched).to contain_exactly(good_formula)
    end

    it "clears fetched state when an API source download fails" do
      bad_formula = formula("bad-source") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      good_formula = formula("good-source") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      failed_download = Homebrew::API::SourceDownload.new(
        "https://brew.sh/bad-source.rb",
        Checksum.new("aa" * 32),
        formula: bad_formula,
      )
      FormulaInstaller.fetched.merge([bad_formula, good_formula])

      expect(described_class.unmark_failed_formulae([failed_download])).to eq([bad_formula.full_name])
      expect(FormulaInstaller.fetched).to contain_exactly(good_formula)
    end

    it "does not clear a same-named formula from another tap" do
      bad_formula = formula("shared-name") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      other_formula = formula("shared-name", tap: Tap.fetch("other", "tap")) do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      failed_resource = bad_formula.resource
      raise "formula resource unavailable" if failed_resource.nil?

      FormulaInstaller.fetched.merge([bad_formula, other_formula])

      expect(described_class.unmark_failed_formulae([failed_resource])).to eq([bad_formula.full_name])
      expect(FormulaInstaller.fetched).to contain_exactly(other_formula)
    end
  end

  describe "::install_formulae" do
    it "only prints the upgrade group for an installed keg-only formula" do
      formula = formula("keg-only") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/keg-only-2.0.tar.gz"
        keg_only :versioned_formula
      end
      (formula.rack/"1.0").mkpath
      tab = Tab.empty
      tab.tabfile = formula.rack/"1.0"/AbstractTab::FILENAME
      tab.write
      Keg.new(formula.rack/"1.0").optlink

      expect do
        described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
      end.to output(<<~EOS).to_stdout
        ==> Would upgrade 1 formula:
        keg-only 1.0 -> 2.0
      EOS
    end

    it "preserves the requested reinstall action for an installed formula" do
      formula = formula("installed") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/installed-2.0.tar.gz"
      end
      formula.prefix.mkpath
      tab = Tab.empty
      tab.tabfile = formula.prefix/AbstractTab::FILENAME
      tab.write

      expect do
        described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)],
                                         dry_run: true, dry_run_action: "reinstall")
      end.to output(<<~EOS).to_stdout
        ==> Would reinstall 1 formula:
        installed 2.0
      EOS
    end

    [nil, "1.0", "2.0"].each do |installed_version|
      it "only lists dependencies with #{installed_version || "no"} version installed" do
        T.bind(self, RSpec::Core::ExampleGroup)

        requested = formula("requested") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/requested-2.0.tar.gz"
        end
        dependency = formula("dependency") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/dependency-1.0.tar.gz"
        end
        if installed_version
          (requested.rack/installed_version).mkpath
          tab = Tab.empty
          tab.tabfile = requested.rack/installed_version/AbstractTab::FILENAME
          tab.write
        end
        installer = FormulaInstaller.new(requested, only_deps: true)
        allow(installer).to receive(:compute_dependencies)
          .and_return([instance_double(Dependency, to_formula: dependency)])

        expect do
          described_class.install_formulae([installer], dry_run: true)
        end.to output(<<~EOS).to_stdout
          ==> Would install 1 dependency for requested:
          dependency
        EOS
      end
    end

    it "does not describe installing the same version as an upgrade" do
      formula = formula("current") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/current-2.0.tar.gz"
      end
      formula.prefix.mkpath
      tab = Tab.empty
      tab.tabfile = formula.prefix/AbstractTab::FILENAME
      tab.write

      expect do
        described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
      end.to output(<<~EOS).to_stdout
        ==> Would install 1 formula:
        current 2.0
      EOS
    end

    [false, true].each do |optlinked|
      it "uses the #{optlinked ? "opt-linked" : "newest"} installed version in the upgrade summary" do
        T.bind(self, RSpec::Core::ExampleGroup)

        formula = formula("multiple") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/multiple-2.0.tar.gz"
        end
        versions = ["1.9", "1.10"]
        versions.each do |version|
          (formula.rack/version).mkpath
          tab = Tab.empty
          tab.tabfile = formula.rack/version/AbstractTab::FILENAME
          tab.write
        end
        Keg.new(formula.rack/"1.9").optlink if optlinked

        expect do
          described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
        end.to output(<<~EOS).to_stdout
          ==> Would upgrade 1 formula:
          multiple #{optlinked ? "1.9" : "1.10"} -> 2.0
        EOS
      end
    end

    it "prints an install plan when the opt link is dangling" do
      formula = formula("stale") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/stale-2.0.tar.gz"
      end
      formula.opt_prefix.dirname.mkpath
      FileUtils.ln_s(formula.rack/"1.0", formula.opt_prefix)

      expect do
        described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
      end.to output(<<~EOS).to_stdout
        ==> Would install 1 formula:
        stale 2.0
      EOS
    end

    [false, true].each do |optlinked|
      it "prints an install plan for a receiptless keg with optlinked=#{optlinked}" do
        T.bind(self, RSpec::Core::ExampleGroup)

        formula = formula("incomplete") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/incomplete-2.0.tar.gz"
        end
        (formula.rack/"1.0").mkpath
        if optlinked
          formula.opt_prefix.dirname.mkpath
          FileUtils.ln_s(formula.rack/"1.0", formula.opt_prefix)
        end

        expect do
          described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
        end.to output(<<~EOS).to_stdout
          ==> Would install 1 formula:
          incomplete 2.0
        EOS
      end

      it "uses the complete keg when a higher receiptless keg has optlinked=#{optlinked}" do
        T.bind(self, RSpec::Core::ExampleGroup)

        formula = formula("mixed") do
          T.bind(self, T.class_of(Formula))
          url "https://brew.sh/mixed-2.0.tar.gz"
        end
        (formula.rack/"1.0").mkpath
        tab = Tab.empty
        tab.tabfile = formula.rack/"1.0"/AbstractTab::FILENAME
        tab.write
        (formula.rack/"1.9").mkpath
        if optlinked
          formula.opt_prefix.dirname.mkpath
          FileUtils.ln_s(formula.rack/"1.9", formula.opt_prefix)
        end

        expect do
          described_class.install_formulae([FormulaInstaller.new(formula, ignore_deps: true)], dry_run: true)
        end.to output(<<~EOS).to_stdout
          ==> Would upgrade 1 formula:
          mixed 1.0 -> 2.0
        EOS
      end
    end

    it "returns installed formulae without cleaning them inline when cleanup is deferred" do
      formula = formula("good-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      formula_installer = instance_double(FormulaInstaller, formula:)

      expect(described_class).to receive(:install_formula).with(formula_installer, upgrade: false)
      expect(Homebrew::Cleanup).not_to receive(:install_formula_clean!)

      expect(described_class.install_formulae([formula_installer], cleanup: false)).to eq([formula])
    end

    it "skips a formula whose install raises and continues with the rest" do
      bad_fi = instance_double(FormulaInstaller, formula: formula("bad-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      good_fi = instance_double(FormulaInstaller, formula: formula("good-bottle") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      allow(Homebrew::Cleanup).to receive(:install_formula_clean!)
      allow(described_class).to receive(:install_formula).with(bad_fi, upgrade: false)
                                                         .and_raise("gzip decompression failed")
      expect(described_class).to receive(:install_formula).with(good_fi, upgrade: false)

      expect { described_class.install_formulae([bad_fi, good_fi]) }
        .to output(/Error: bad-bottle: gzip decompression failed/).to_stderr
    end

    it "skips a formula whose build fails and continues with the rest" do
      bad_formula = formula("bad-build") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      bad_fi = instance_double(FormulaInstaller, formula: bad_formula)
      good_fi = instance_double(FormulaInstaller, formula: formula("good-build") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end)
      error = BuildError.new(bad_formula, "make", ["install"], {})

      allow(Homebrew::Cleanup).to receive(:install_formula_clean!)
      allow(described_class).to receive(:install_formula).with(bad_fi, upgrade: false).and_raise(error)
      expect(described_class).to receive(:install_formula).with(good_fi, upgrade: false)
      expect(Utils::Analytics).to receive(:report_build_error).with(error)
      expect(error).to receive(:dump).with(verbose: false)

      expect(described_class.install_formulae([bad_fi, good_fi])).to eq([good_fi.formula])
    end
  end

  describe "::finish_installation" do
    it "cleans packages before reporting caveats" do
      formula = instance_double(Formula)
      cask = instance_double(Cask::Cask)

      expect(Homebrew::Cleanup).to receive(:install_clean!)
        .with(formulae: [formula], casks: [cask])
        .ordered
      expect(Homebrew::Cleanup).to receive(:periodic_clean!).with(dry_run: false).ordered
      expect(Homebrew.messages).to receive(:display_messages)
        .with(force_caveats: true, display_times: true)
        .ordered

      described_class.finish_installation(formulae: [formula], casks: [cask], display_times: true)
    end
  end

  describe "::enqueue_cask_installers" do
    it "returns the installers whose downloads were enqueued" do
      installer = instance_double(Cask::Installer)

      expect(installer).to receive(:enqueue_downloads)

      expect(described_class.enqueue_cask_installers([installer])).to eq([installer])
    end

    it "skips casks whose enqueue raises and continues with the rest" do
      bad_installer = instance_double(Cask::Installer, cask: instance_double(Cask::Cask, to_s: "bad-cask"))
      allow(bad_installer).to receive(:enqueue_downloads)
        .and_raise(URI::InvalidURIError, 'bad URI (is not URI?): "https://example.com/bad -cask.dmg"')
      good_installer = instance_double(Cask::Installer, enqueue_downloads: nil)

      expect do
        expect(described_class.enqueue_cask_installers([bad_installer, good_installer])).to eq([good_installer])
      end.to output(/Error: bad-cask: bad URI/).to_stderr
    end
  end

  describe "::fetch_cask_dependencies" do
    it "enqueues dependency downloads once the cask downloads have been fetched" do
      installer = instance_double(Cask::Installer)
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [])

      expect(installer).to receive(:enqueue_dependency_downloads).ordered
      expect(download_queue).to receive(:fetch).with(heading: "Fetching dependency downloads").ordered

      described_class.fetch_cask_dependencies([installer], download_queue:)
    end

    it "marks casks whose downloads failed before resolving dependencies" do
      downloader = instance_double(Cask::Download)
      installer = instance_double(Cask::Installer, downloader:, enqueue_dependency_downloads: nil)
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [downloader], fetch: nil)

      allow(installer).to receive(:download_failed?).and_return(false, true)
      expect(installer).to receive(:download_failed!).ordered
      expect(installer).to receive(:enqueue_dependency_downloads).ordered

      described_class.fetch_cask_dependencies([installer], download_queue:)
    end

    it "skips casks whose dependency resolution raises and continues with the rest" do
      bad_installer = instance_double(Cask::Installer, cask: instance_double(Cask::Cask, to_s: "bad-cask"))
      allow(bad_installer).to receive(:enqueue_dependency_downloads).and_raise("unexpected nil primary_container")
      good_installer = instance_double(Cask::Installer)
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [], fetch: nil)

      expect(good_installer).to receive(:enqueue_dependency_downloads)

      expect { described_class.fetch_cask_dependencies([bad_installer, good_installer], download_queue:) }
        .to output(/Error: bad-cask: unexpected nil primary_container/).to_stderr
    end
  end

  describe "::mark_failed_cask_downloads" do
    it "marks cask installers whose downloads failed" do
      downloader = instance_double(Cask::Download)
      installer = instance_double(Cask::Installer, downloader:, download_failed?: false)
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [downloader])

      expect(installer).to receive(:download_failed!)

      described_class.mark_failed_cask_downloads([installer], download_queue:)
    end

    it "marks dependency cask installers whose downloads failed" do
      dependency_downloader = instance_double(Cask::Download)
      dependency_installer = instance_double(Cask::Installer, downloader:       dependency_downloader,
                                                              download_failed?: false)
      installer = instance_double(Cask::Installer, downloader:                 instance_double(Cask::Download),
                                                   download_failed?:           false,
                                                   dependency_cask_installers: [dependency_installer])
      download_queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [dependency_downloader])

      expect(installer).not_to receive(:download_failed!)
      expect(dependency_installer).to receive(:download_failed!)

      described_class.mark_failed_cask_downloads([installer], download_queue:)
    end
  end

  describe "::print_dry_run_dependencies" do
    it "splits fresh installs and upgrades under separate headers" do
      fresh = formula("fresh-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      installed = formula("installed-dep") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(fresh).to receive(:any_version_installed?).and_return(false)
      allow(installed).to receive(:any_version_installed?).and_return(true)
      deps = [
        instance_double(Dependency, to_formula: fresh),
        instance_double(Dependency, to_formula: installed),
      ]

      expect { described_class.print_dry_run_dependencies(Testball.new, deps, &:name) }
        .to output(/Would install 1 dependency.*fresh-dep.*Would upgrade 1 dependency.*installed-dep/m).to_stdout
    end
  end
end
