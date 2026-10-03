# typed: true
# frozen_string_literal: true

require "test/support/fixtures/testball"
require "cleanup"
require "utils/autoremove"
require "cask/cache"
require "uninstall"
require "fileutils"

RSpec.describe Homebrew::Cleanup do
  subject(:cleanup) { described_class.new }

  let(:ds_store) { Pathname.new("#{HOMEBREW_CELLAR}/.DS_Store") }
  let(:lock_file) { Pathname.new("#{HOMEBREW_LOCKS}/foo") }

  before do
    FileUtils.touch ds_store
    FileUtils.touch lock_file
    FileUtils.mkdir_p HOMEBREW_LIBRARY/"Homebrew/vendor"
    FileUtils.touch HOMEBREW_LIBRARY/"Homebrew/vendor/portable-ruby-version"
  end

  after do
    FileUtils.rm_f ds_store
    FileUtils.rm_f lock_file
    FileUtils.rm_rf HOMEBREW_LIBRARY/"Homebrew"
  end

  describe "#cleanup_lockfiles" do
    it "preserves active locks" do
      lock_file.open(File::RDWR) do |file|
        file.flock(File::LOCK_EX | File::LOCK_NB)

        cleanup.cleanup_lockfiles

        expect(lock_file).to exist
      end
    end

    it "skips a lock replaced by a symlink before it is opened" do
      allow(lock_file).to receive(:readable?) do
        lock_file.unlink
        lock_file.make_symlink(ds_store)
        true
      end

      cleanup.cleanup_lockfiles(lock_file)

      expect(lock_file).to be_a_symlink
    end

    it "preserves a replacement lock acquired after opening the original" do
      allow(lock_file).to receive(:open).and_wrap_original do |original, *args, &block|
        original.call(*args) do |file|
          lock_file.unlink
          original.call(File::RDWR | File::CREAT) do |replacement|
            replacement.flock(File::LOCK_EX | File::LOCK_NB)
            block.call(file)
          end
        end
      end

      cleanup.cleanup_lockfiles(lock_file)

      expect(lock_file).to exist
    end

    it "ignores lock files deleted before they are opened" do
      allow(lock_file).to receive(:readable?) do
        lock_file.unlink
        true
      end

      expect { cleanup.cleanup_lockfiles(lock_file) }.not_to raise_error
    end
  end

  describe "::install_formula_clean!" do
    it "does not report a formula when nothing was cleaned" do
      formula = Testball.new

      allow(described_class).to receive(:install_cleanup_formulae).with([formula]).and_return([formula])
      expect_any_instance_of(described_class).to receive(:cleanup_formula).with(formula, quiet: true)

      with_env(HOMEBREW_NO_ENV_HINTS: "1") do
        expect { described_class.install_formula_clean!(formula) }.not_to output.to_stdout
      end
    end

    it "reports a formula when it was cleaned" do
      formula = Testball.new
      stale_path = mktmpdir/"testball--0.0"
      stale_path.write "stale"

      allow(described_class).to receive(:install_cleanup_formulae).with([formula]).and_return([formula])
      expect_any_instance_of(described_class).to receive(:cleanup_formula)
        .with(formula, quiet: true) do |cleanup, package, **|
        expect(package).to be(formula)
        cleanup.cleanup_path(stale_path) { stale_path.unlink }
      end

      with_env(HOMEBREW_NO_ENV_HINTS: "1") do
        expect { described_class.install_formula_clean!(formula) }.to output(<<~EOS).to_stdout
          ==> Running `brew cleanup testball`...
          Removing: #{stale_path}... (#{stale_path.abv})
        EOS
      end
    end
  end

  describe "::install_clean!" do
    it "does not report formulae and casks when nothing was cleaned", :cask do
      formula = Testball.new
      cask = Cask::Cask.new("local-caffeine")

      allow(described_class).to receive(:install_cleanup_formulae).with([formula]).and_return([formula])
      expect(Utils).to receive(:parallel_map).with([formula, cask]).and_call_original
      expect_any_instance_of(described_class).to receive(:cleanup_formula)
        .with(formula, quiet: true, cache_db: false, cleanup_unreferenced: false)
      expect_any_instance_of(described_class).to receive(:cleanup_cask)
        .with(cask, cleanup_unreferenced: false)
      expect_any_instance_of(described_class).to receive(:cleanup_cache_db).with(no_args)
      expect_any_instance_of(described_class).to receive(:cleanup_unreferenced_downloads).with(no_args)

      with_env(HOMEBREW_NO_ENV_HINTS: "1") do
        expect { described_class.install_clean!(formulae: [formula], casks: [cask]) }.not_to output.to_stdout
      end
    end

    it "reports cleanup paths in real time without package headings", :cask do
      formula = Testball.new
      cask = Cask::Cask.new("local-caffeine")
      stale_path = mktmpdir/"testball--0.0"
      stale_path.write "stale"

      allow(described_class).to receive(:install_cleanup_formulae).with([formula]).and_return([formula])
      expect_any_instance_of(described_class).to receive(:cleanup_formula) do |cleanup, package, **|
        expect(package).to be(formula)
        cleanup.cleanup_path(stale_path) do
          expect($stdout.string).to include("Removing: #{stale_path}...")
          stale_path.unlink
        end
      end
      expect_any_instance_of(described_class).to receive(:cleanup_cask)
        .with(cask, cleanup_unreferenced: false)
      expect_any_instance_of(described_class).to receive(:cleanup_cache_db).with(no_args)
      expect_any_instance_of(described_class).to receive(:cleanup_unreferenced_downloads).with(no_args)

      with_env(HOMEBREW_NO_ENV_HINTS: "1") do
        expect { described_class.install_clean!(formulae: [formula], casks: [cask]) }.to output(<<~EOS).to_stdout
          ==> Cleanup
          Removing: #{stale_path}... (#{stale_path.abv})
        EOS
      end
    end
  end

  describe "::prune?" do
    subject(:path) { HOMEBREW_CACHE/"foo" }

    before do
      path.mkpath
    end

    it "returns true when ctime and mtime < days_default" do
      allow_any_instance_of(Pathname).to receive(:ctime).and_return((DateTime.now - 2).to_time)
      allow_any_instance_of(Pathname).to receive(:mtime).and_return((DateTime.now - 2).to_time)
      expect(described_class.prune?(path, 1)).to be true
    end

    it "returns false when ctime and mtime >= days_default" do
      expect(described_class.prune?(path, 2)).to be false
    end
  end

  describe "::cleanup" do
    it "cleans installed casks during periodic cleanup", :cask do
      cask = Cask::Cask.new("local-caffeine")
      ENV["HOMEBREW_NO_AUTOREMOVE"] = "1"
      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])

      expect(cleanup).to receive(:cleanup_cask)
        .with(cask, ds_store: false, cleanup_legacy_downloads: false, cleanup_unreferenced: false)

      cleanup.clean!(periodic: true)
    end

    it "removes .DS_Store and lock files" do
      cleanup.clean!

      expect(ds_store).not_to exist
      expect(lock_file).not_to exist
    end

    it "doesn't remove anything if `dry_run` is true" do
      described_class.new(dry_run: true).clean!

      expect(ds_store).to exist
      expect(lock_file).to exist
    end

    it "removes leftover `.reinstall` kegs in the Cellar" do
      reinstall_keg = HOMEBREW_CELLAR/"foo/1.0.reinstall"
      reinstall_keg.mkpath

      cleanup.clean!

      expect(reinstall_keg).not_to exist
    end

    it "doesn't remove the lock file if it is locked" do
      lock_file.open(File::RDWR | File::CREAT) do |file|
        file.flock(File::LOCK_EX | File::LOCK_NB)
        GC.start

        cleanup.clean!

        expect(lock_file).to exist
      end
    end

    it "cleans up unreferenced downloads once, however many formulae are installed" do
      ENV["HOMEBREW_NO_AUTOREMOVE"] = "1"
      installed = ["foo", "bar", "baz"].map do |name|
        instance_double(Formula, name:, eligible_kegs_for_cleanup: [])
      end
      allow(Formula).to receive(:installed).and_return(installed)

      expect(cleanup).to receive(:cleanup_unreferenced_downloads).once.and_call_original

      cleanup.clean!
    end

    it "doesn't load untrusted installed formulae while cleaning the cache" do
      cache_file = HOMEBREW_CACHE/"untrusted--1.0"
      cache_file.write "cached"
      (HOMEBREW_CELLAR/"untrusted/1.0").mkpath

      expect(Formulary).to receive(:from_rack).with(HOMEBREW_CELLAR/"untrusted")
                                              .and_raise(Homebrew::UntrustedTapError)

      expect { cleanup.cleanup_cache([{ path: cache_file, type: nil }]) }
        .to output(/Skipping untrusted: tap formula is not trusted/).to_stderr
      expect(cache_file).to exist
    end

    context "when it can't remove a keg" do
      let(:formula_zero_dot_one) { Class.new(Testball) { version "0.1" }.new }
      let(:formula_zero_dot_two) { Class.new(Testball) { version "0.2" }.new }

      before do
        [formula_zero_dot_one, formula_zero_dot_two].each do |f|
          f.brew do
            f.install
          end

          Tab.create(f, DevelopmentTools.default_compiler, :libcxx).write
        end

        allow_any_instance_of(Keg)
          .to receive(:uninstall)
          .and_raise(Errno::EACCES)
      end

      it "doesn't remove any kegs" do
        cleanup.cleanup_formula formula_zero_dot_one
        expect(formula_zero_dot_one.installed_kegs.size).to eq(2)
      end

      it "lists the unremovable kegs" do
        cleanup.cleanup_formula formula_zero_dot_two
        expect(cleanup.unremovable_kegs).to contain_exactly(formula_zero_dot_one.installed_kegs[0])
      end
    end
  end

  describe "::autoremove" do
    let(:removable_keg) { instance_double(Keg, name: "libthai") }
    let(:removable_formula) do
      instance_double(Formula, name: "libthai", full_name: "libthai", any_installed_keg: removable_keg)
    end

    before do
      allow(Formula).to receive(:clear_cache)
      allow(Formula).to receive(:installed).and_return([removable_formula])
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      allow(Homebrew::EnvConfig).to receive(:no_cleanup_formulae).and_return([])
      allow(Utils::Autoremove).to receive(:removable_formulae).with([removable_formula],
                                                                    []).and_return([removable_formula])
      allow(InstalledDependents).to receive(:find_some_installed_dependents)
        .with([removable_keg])
        .and_return([[removable_keg], ["pango"]])
    end

    it "does not print or uninstall formulae required by installed dependents" do
      expect(Homebrew::Uninstall).not_to receive(:uninstall_kegs)

      expect { described_class.autoremove }.not_to output.to_stdout
    end
  end

  describe "::prune_prefix_symlinks_and_directories" do
    let(:lib) { HOMEBREW_PREFIX/"lib" }

    before do
      lib.mkpath
    end

    it "keeps required empty directories" do
      cleanup.prune_prefix_symlinks_and_directories
      expect(lib).to exist
      expect(lib.children).to be_empty
    end

    it "removes broken symlinks" do
      FileUtils.ln_s lib/"foo", lib/"bar"
      FileUtils.touch lib/"baz"

      cleanup.prune_prefix_symlinks_and_directories
      expect(lib).to exist
      expect(lib.children).to eq([lib/"baz"])
    end

    it "removes empty directories" do
      dir = lib/"test"
      dir.mkpath
      file = lib/"keep/file"
      file.dirname.mkpath
      FileUtils.touch file

      cleanup.prune_prefix_symlinks_and_directories
      expect(dir).not_to exist
      expect(file).to exist
    end

    context "when nested directories exist with only broken symlinks" do
      let(:dir) { HOMEBREW_PREFIX/"lib/foo" }
      let(:child_dir) { dir/"bar" }
      let(:grandchild_dir) { child_dir/"baz" }
      let(:broken_link) { dir/"broken" }
      let(:link_to_broken_link) { child_dir/"another-broken" }

      before do
        grandchild_dir.mkpath
        FileUtils.ln_s dir/"missing", broken_link
        FileUtils.ln_s broken_link, link_to_broken_link
      end

      it "removes broken symlinks and resulting empty directories" do
        cleanup.prune_prefix_symlinks_and_directories
        expect(dir).not_to exist
      end

      it "doesn't remove anything and only prints removal steps if `dry_run` is true" do
        expect do
          described_class.new(dry_run: true).prune_prefix_symlinks_and_directories
        end.to output(<<~EOS).to_stdout
          Would remove (broken link): #{link_to_broken_link}
          Would remove (broken link): #{broken_link}
          Would remove (empty directory): #{grandchild_dir}
          Would remove (empty directory): #{child_dir}
          Would remove (empty directory): #{dir}
        EOS

        expect(broken_link).to be_a_symlink
        expect(link_to_broken_link).to be_a_symlink
        expect(grandchild_dir).to exist
      end
    end

    it "removes broken symlinks for uninstalled migrated Casks" do
      caskroom = Cask::Caskroom.path
      old_cask_dir = caskroom/"old"
      new_cask_dir = caskroom/"new"
      unrelated_cask_dir = caskroom/"other"
      unrelated_cask_dir.mkpath
      FileUtils.ln_s new_cask_dir, old_cask_dir

      cleanup.prune_prefix_symlinks_and_directories
      expect(unrelated_cask_dir).to exist
      expect(old_cask_dir).not_to be_a_symlink
      expect(old_cask_dir).not_to exist
    end
  end

  specify "::cleanup_formula" do
    f1 = Class.new(Testball) do
      version "1.0"
    end.new

    f2 = Class.new(Testball) do
      version "0.2"
      version_scheme 1
    end.new

    f3 = Class.new(Testball) do
      version "0.3"
      version_scheme 1
    end.new

    f4 = Class.new(Testball) do
      version "0.1"
      version_scheme 2
    end.new

    [f1, f2, f3, f4].each do |f|
      f.brew do
        f.install
      end

      Tab.create(f, DevelopmentTools.default_compiler, :libcxx).write
    end

    expect(f1).to be_latest_version_installed
    expect(f2).to be_latest_version_installed
    expect(f3).to be_latest_version_installed
    expect(f4).to be_latest_version_installed

    cleanup.cleanup_formula f3

    expect(f1).not_to be_latest_version_installed
    expect(f2).not_to be_latest_version_installed
    expect(f3).to be_latest_version_installed
    expect(f4).to be_latest_version_installed
  end

  describe "#formula_cache_paths" do
    let(:cache) { mktmpdir/"cache" }
    let(:testball) { instance_double(Formula, name: "testball") }

    before do
      cache.mkpath
    end

    it "returns only the formula's own downloads and bottle manifests" do
      matching = [
        cache/"testball--1.0.tar.gz",
        cache/"testball--rsrc--1.0.txt",
        cache/"testball_bottle_manifest--1.0.bottle_manifest.json",
      ]
      non_matching = [
        cache/".testball--1.0.tar.gz",
        cache/"testball-foo--1.0.tar.gz",
        cache/"testball_bottle_manifest",
        cache/"testballs--1.0.tar.gz",
      ]
      (matching + non_matching).each { |path| FileUtils.touch path }

      expect(described_class.new(cache:).formula_cache_paths(testball)).to eq(matching)
    end

    it "reads the cache directory only once for multiple formulae" do
      cleanup = described_class.new(cache:)

      expect(cache).to receive(:children).once.and_return([cache/"testball--1.0.tar.gz"])

      cleanup.formula_cache_paths(testball)
      cleanup.formula_cache_paths(instance_double(Formula, name: "other"))
    end
  end

  describe "#cleanup_temp_staging" do
    it "removes leftover staged cask downloads" do
      staged_path = HOMEBREW_TEMP_CASKROOM/"local-caffeine/1.2.3"
      staged_path.mkpath
      FileUtils.ln_s staged_path, "#{staged_path}.staged"

      cleanup.cleanup_temp_staging

      expect(HOMEBREW_TEMP_CASKROOM/"local-caffeine").not_to exist
    end

    it "warns and continues when a leftover cannot be removed" do
      read_only = HOMEBREW_TEMP_CASKROOM/"a-read-only/1.0/App.app/Contents"
      (read_only/"file").dirname.mkpath
      FileUtils.touch read_only/"file"
      read_only.chmod 0555
      removable = HOMEBREW_TEMP_CASKROOM/"b-removable/1.0"
      removable.mkpath

      expect { cleanup.cleanup_temp_staging }.to output(/Permission denied/).to_stderr
      expect(HOMEBREW_TEMP_CASKROOM/"b-removable").not_to exist
    ensure
      read_only&.chmod 0755
    end
  end

  describe "#cleanup_cask", :cask do
    before do
      Cask::Cache.path.mkpath
    end

    context "when given a versioned cask" do
      let(:cask) { Cask::CaskLoader.load("local-transmission") }

      it "removes the download if it is not for the latest version" do
        download = Cask::Cache.path/"#{cask.token}--7.8.9"

        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).not_to exist
      end

      it "removes legacy URL-basename downloads if they are not for the latest version" do
        download = Cask::Cache.path/"transmission-2.61.dmg--7.8.9.dmg"

        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).not_to exist
      end

      it "does not remove downloads for the latest version" do
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}"

        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).to exist
      end

      it "removes legacy URL-basename downloads when the token-named download exists" do
        legacy_download = Cask::Cache.path/"transmission-2.61.dmg--#{cask.version}.dmg"
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}.dmg"

        FileUtils.touch legacy_download
        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect([legacy_download.exist?, download.exist?]).to eq([false, true])
      end

      it "does not remove downloads when the latest version ends with a comma" do
        version = Cask::DSL::Version.new("7.2,2023.3,")
        cask = instance_double(Cask::Cask,
                               token:             "trailing-comma",
                               version:,
                               installed_version: version,
                               url:               nil,
                               caskroom_path:     Cask::Caskroom.path/"trailing-comma")
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}.zip"

        allow(Cask::CaskLoader).to receive(:load).with(cask.token, warn: false).and_return(cask)
        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).to exist
      end

      it "removes downloads when the cask has no version on the current system" do
        cask = instance_double(Cask::Cask,
                               token:             "macos-only",
                               version:           nil,
                               installed_version: nil,
                               url:               nil,
                               caskroom_path:     Cask::Caskroom.path/"macos-only")
        download = Cask::Cache.path/"#{cask.token}--1.0.AppImage"

        allow(Cask::CaskLoader).to receive(:load).with(cask.token, warn: false).and_return(cask)
        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).not_to exist
      end
    end

    context "when given a `:latest` cask" do
      let(:cask) { Cask::CaskLoader.load("latest") }

      it "does not remove the download for the latest version" do
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}"

        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).to exist
      end

      it "removes the download for the latest version after 30 days" do
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}"

        allow(download).to receive_messages(ctime: (DateTime.now - 30).to_time - (60 * 60),
                                            mtime: (DateTime.now - 30).to_time - (60 * 60))

        cleanup.cleanup_cask(cask)

        expect(download).not_to exist
      end

      it "removes broken legacy URL-basename downloads" do
        version = Cask::DSL::Version.new(:latest)
        cask = instance_double(Cask::Cask,
                               token:         "latest-cask",
                               version:,
                               url:           "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip",
                               caskroom_path: Cask::Caskroom.path/"latest-cask")
        download = Cask::Cache.path/"caffeine.zip--#{version}.zip"

        FileUtils.ln_s Cask::Cache.path/"missing.zip", download

        cleanup.cleanup_cask(cask)

        expect(download).not_to be_a_symlink
      end
    end
  end

  describe "::cleanup_logs" do
    let(:path) { HOMEBREW_LOGS/"delete_me" }

    before do
      path.mkpath
    end

    it "cleans all logs if prune is 0" do
      described_class.new(days: 0).cleanup_logs
      expect(path).not_to exist
    end

    it "cleans up logs if older than 30 days" do
      allow_any_instance_of(Pathname).to receive(:ctime).and_return((DateTime.now - 31).to_time)
      allow_any_instance_of(Pathname).to receive(:mtime).and_return((DateTime.now - 31).to_time)
      cleanup.cleanup_logs
      expect(path).not_to exist
    end

    it "does not clean up logs less than 30 days old" do
      allow_any_instance_of(Pathname).to receive(:ctime).and_return((DateTime.now - 15).to_time)
      allow_any_instance_of(Pathname).to receive(:mtime).and_return((DateTime.now - 15).to_time)
      cleanup.cleanup_logs
      expect(path).to exist
    end
  end

  describe "::cleanup_bootsnap" do
    it "removes stale keys and keeps the current key" do
      cache = mktmpdir
      current = cache/"bootsnap/current"
      stale = cache/"bootsnap/stale"
      current.mkpath
      stale.mkpath
      allow(Homebrew::Bootsnap).to receive(:key).and_return("current")

      described_class.new(cache:).cleanup_bootsnap

      expect([current.exist?, stale.exist?]).to eq([true, false])
    end
  end

  describe "::cleanup_cache" do
    it "removes legacy cask downloads during full cache cleanup", :cask do
      cask = Cask::CaskLoader.load("local-transmission")
      download = Cask::Cache.path/"transmission-2.61.dmg--7.8.9.dmg"

      Cask::Cache.path.mkpath
      FileUtils.touch download
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])

      cleanup.cleanup_cache

      expect(download).not_to exist
    end

    it "cleans up incomplete downloads" do
      incomplete = (HOMEBREW_CACHE/"something.incomplete")
      incomplete.mkpath

      cleanup.cleanup_cache

      expect(incomplete).not_to exist
    end

    it "cleans up 'cargo_cache'" do
      cargo_cache = (HOMEBREW_CACHE/"cargo_cache")
      cargo_cache.mkpath

      cleanup.cleanup_cache

      expect(cargo_cache).not_to exist
    end

    it "cleans up 'go_cache'" do
      go_cache = (HOMEBREW_CACHE/"go_cache")
      go_cache.mkpath

      cleanup.cleanup_cache

      expect(go_cache).not_to exist
    end

    it "cleans up 'bundler_cache'" do
      bundler_cache = (HOMEBREW_CACHE/"bundler_cache")
      bundler_cache.mkpath

      cleanup.cleanup_cache

      expect(bundler_cache).not_to exist
    end

    it "prunes only old files from the content-addressed 'npm_cache'" do
      npm_cache = (HOMEBREW_CACHE/"npm_cache")
      old_file = npm_cache/"_cacache/old"
      new_file = npm_cache/"_cacache/new"
      [old_file, new_file].each do |file|
        file.dirname.mkpath
        file.write ""
      end
      allow(described_class).to receive(:prune?).and_return(false)
      allow(described_class).to receive(:prune?).with(old_file, anything).and_return(true)

      cleanup.cleanup_cache

      expect(old_file).not_to exist
      expect(new_file).to exist
    end

    it "cleans up 'glide_home'" do
      glide_home = (HOMEBREW_CACHE/"glide_home")
      glide_home.mkpath

      cleanup.cleanup_cache

      expect(glide_home).not_to exist
    end

    it "cleans up 'java_cache'" do
      java_cache = (HOMEBREW_CACHE/"java_cache")
      java_cache.mkpath

      cleanup.cleanup_cache

      expect(java_cache).not_to exist
    end

    it "keeps the content-addressed 'npm_cache'" do
      npm_cache = (HOMEBREW_CACHE/"npm_cache")
      npm_cache.mkpath

      cleanup.cleanup_cache

      expect(npm_cache).to exist
    end

    it "cleans up 'gclient_cache'" do
      gclient_cache = (HOMEBREW_CACHE/"gclient_cache")
      gclient_cache.mkpath

      cleanup.cleanup_cache

      expect(gclient_cache).not_to exist
    end

    it "cleans up all files and directories" do
      git = (HOMEBREW_CACHE/"gist--git")
      gist = (HOMEBREW_CACHE/"gist")
      svn = (HOMEBREW_CACHE/"gist--svn")

      git.mkpath
      gist.mkpath
      FileUtils.touch svn

      described_class.new(days: 0).cleanup_cache

      expect(git).not_to exist
      expect(gist).to exist
      expect(svn).not_to exist
    end

    it "does not clean up directories that are not VCS checkouts" do
      git = (HOMEBREW_CACHE/"git")
      git.mkpath

      described_class.new(days: 0).cleanup_cache

      expect(git).to exist
    end

    it "cleans up VCS checkout directories with modified time < prune time" do
      foo = (HOMEBREW_CACHE/"--foo")
      foo.mkpath
      allow_any_instance_of(Pathname).to receive(:ctime).and_return(Time.now - (2 * 60 * 60 * 24))
      allow_any_instance_of(Pathname).to receive(:mtime).and_return(Time.now - (2 * 60 * 60 * 24))
      described_class.new(days: 1).cleanup_cache
      expect(foo).not_to exist
    end

    it "does not clean up VCS checkout directories with modified time >= prune time" do
      foo = (HOMEBREW_CACHE/"--foo")
      foo.mkpath
      described_class.new(days: 1).cleanup_cache
      expect(foo).to exist
    end

    it "does not clean up internal package API files without scrub even when pruning" do
      api_package_files = [
        HOMEBREW_CACHE/"api/internal/packages.arm64_golden_gate.jws.json",
        HOMEBREW_CACHE/"api/internal/packages.arm64_tahoe.jws.json",
      ]
      api_package_files.each do |api_package_file|
        api_package_file.dirname.mkpath
        FileUtils.touch api_package_file
      end

      described_class.new(days: 0).cleanup_cache

      expect(api_package_files.map(&:exist?)).to eq([true, true])
    end

    it "cleans up per-resource API files when pruning" do
      cache = mktmpdir/"cache"
      api_resource_files = [cache/"api/cask/foo.json", cache/"api/formula/foo.json"]
      api_resource_files.each do |file|
        file.dirname.mkpath
        FileUtils.touch file
      end

      described_class.new(days: 0, cache:).cleanup_cache

      expect(api_resource_files.map(&:exist?)).to eq([false, false])
    end

    it "cleans up per-resource API files with scrub" do
      cache = mktmpdir/"cache"
      api_resource_files = [cache/"api/cask/foo.json", cache/"api/formula/foo.json"]
      api_resource_files.each do |file|
        file.dirname.mkpath
        FileUtils.touch file
      end

      described_class.new(scrub: true, cache:).cleanup_cache

      expect(api_resource_files.map(&:exist?)).to eq([false, false])
    end

    it "cleans up non-current internal package API files with scrub" do
      cache = mktmpdir/"cache"
      api_internal = cache/"api/internal"
      current_api_package_file = api_internal/Homebrew::API::Internal.cached_packages_json_file_path.basename
      stale_api_package_file = api_internal/"packages.stale.jws.json"
      api_package_files = [current_api_package_file, stale_api_package_file]
      api_jws_files = [
        cache/"api/formula.jws.json",
        cache/"api/cask.jws.json",
      ]
      api_package_files.each do |api_package_file|
        api_package_file.dirname.mkpath
        FileUtils.touch api_package_file
      end
      api_jws_files.each do |api_jws_file|
        api_jws_file.dirname.mkpath
        FileUtils.touch api_jws_file
      end

      described_class.new(scrub: true, cache:).cleanup_cache

      expect([*api_package_files, *api_jws_files].map(&:exist?)).to eq([true, false, true, true])
    end

    it "cleans up non-current internal package API payload sidecars with scrub" do
      cache = mktmpdir/"cache"
      api_internal = cache/"api/internal"
      current_basename = Homebrew::API::Internal.cached_packages_json_file_path.basename
      kept_files = [
        api_internal/current_basename,
        api_internal/"#{current_basename}.payload",
        api_internal/"#{current_basename}.payload.index",
      ]
      scrubbed_files = [
        api_internal/"packages.stale.jws.json.payload",
        api_internal/"packages.stale.jws.json.payload.index",
        api_internal/"#{current_basename}.payload.tmp",
      ]
      (kept_files + scrubbed_files).each do |file|
        file.dirname.mkpath
        FileUtils.touch file
      end

      described_class.new(scrub: true, cache:).cleanup_cache

      expect((kept_files + scrubbed_files).map(&:exist?)).to eq([true, true, true, false, false, false])
    end

    it "cleans up API source files and symlinks at any depth without cleaning directories" do
      root_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/README.md"
      nested_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/Formula/a/testball.rb"
      nested_symlink = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/patches/subdir/noop-a.diff"
      nested_directory = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/patches/keep"
      symlink_target = mktmpdir/"noop-a.diff"

      root_file.dirname.mkpath
      nested_file.dirname.mkpath
      nested_symlink.dirname.mkpath
      nested_directory.mkpath
      FileUtils.touch root_file
      FileUtils.touch nested_file
      FileUtils.touch symlink_target
      FileUtils.ln_s symlink_target, nested_symlink

      described_class.new(days: 0).cleanup_cache

      expect([root_file.exist?, nested_file.exist?, nested_symlink.exist?, nested_directory.exist?])
        .to eq([false, false, false, true])
    end

    it "does not remove recent API source local patches as stale" do
      patch_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/patches/noop-a.diff"
      nested_patch_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/patches/subdir/noop-b.diff"
      patch_file.dirname.mkpath
      nested_patch_file.dirname.mkpath
      FileUtils.touch patch_file
      FileUtils.touch nested_patch_file

      cleanup.cleanup_cache

      expect([patch_file.exist?, nested_patch_file.exist?]).to eq([true, true])
    end

    it "keeps current API formula source paths when tap git head matches" do
      source_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/Formula/testball.rb"
      nested_source_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-core/abc123/Formula/a/testball.rb"
      package = instance_double(Formula, tap_git_head: "abc123")
      source_file.dirname.mkpath
      nested_source_file.dirname.mkpath
      FileUtils.touch source_file
      FileUtils.touch nested_source_file
      expect(Formulary).to receive(:factory).with("Homebrew/homebrew-core/testball").twice.and_return(package)

      cleanup.cleanup_cache([{ path: source_file, type: :api_source },
                             { path: nested_source_file, type: :api_source }])

      expect([source_file.exist?, nested_source_file.exist?]).to eq([true, true])
    end

    it "removes cached API cask source paths" do
      source_file = HOMEBREW_CACHE/"api-source/Homebrew/homebrew-cask/abc123/Cask/testball.rb"
      source_file.dirname.mkpath
      FileUtils.touch source_file

      cleanup.cleanup_cache([{ path: source_file, type: :api_source }])

      expect(source_file).not_to exist
    end

    context "when cleaning old files in HOMEBREW_CACHE" do
      let(:bottle) { HOMEBREW_CACHE/"testball--0.0.1.tag.bottle.tar.gz" }
      let(:testball) { HOMEBREW_CACHE/"testball--0.0.1" }
      let(:testball_resource) { HOMEBREW_CACHE/"testball--rsrc--0.0.1.txt" }

      before do
        FileUtils.touch bottle
        FileUtils.touch testball
        FileUtils.touch testball_resource
        (HOMEBREW_CELLAR/"testball"/"0.0.1").mkpath
        # Create the latest version of testball so the older version is eligible for cleanup.
        (HOMEBREW_CELLAR/"testball"/"0.1/bin").mkpath
        FileUtils.touch(CoreTap.instance.new_formula_path("testball"))
      end

      it "cleans up file if outdated" do
        allow(Utils::Bottles).to receive(:file_outdated?).with(any_args).and_return(true)
        cleanup.cleanup_cache
        expect(bottle).not_to exist
        expect(testball).not_to exist
        expect(testball_resource).not_to exist
      end

      it "cleans up file if `scrub` is true and formula not installed" do
        described_class.new(scrub: true).cleanup_cache
        expect(bottle).not_to exist
        expect(testball).not_to exist
        expect(testball_resource).not_to exist
      end

      it "cleans up file if stale" do
        cleanup.cleanup_cache
        expect(bottle).not_to exist
        expect(testball).not_to exist
        expect(testball_resource).not_to exist
      end
    end

    context "when the cache path is a bottle manifest file" do
      let(:bottle_manifest_path) { HOMEBREW_CACHE/"testball_bottle_manifest--1.0.bottle_manifest.json" }

      before do
        HOMEBREW_CACHE.mkpath
        FileUtils.touch bottle_manifest_path
        (HOMEBREW_CELLAR/"testball"/"0.1/bin").mkpath
        FileUtils.touch(CoreTap.instance.new_formula_path("testball"))
      end

      it "does not remove the file when bottle resource version is nil" do
        allow(Formulary).to receive(:from_rack).with(HOMEBREW_CELLAR/"testball_bottle_manifest").and_return(nil)
        allow(Formulary).to receive(:from_rack).and_call_original
        allow(Formulary).to receive(:from_rack).with(HOMEBREW_CELLAR/"testball").and_wrap_original do |m, *args|
          formula = m.call(*args)
          if formula
            bottle_nil_version = instance_double(Bottle,
                                                 resource: instance_double(Resource, version: nil),
                                                 rebuild:  0)
            allow(formula).to receive(:bottle).and_return(bottle_nil_version)
          end
          formula
        end
        cleanup.cleanup_cache([{ path: bottle_manifest_path, type: nil }])
        expect(bottle_manifest_path).to exist
      end

      it "removes the file when path version differs from bottle version_rebuild" do
        pathname_mismatch = (HOMEBREW_CACHE/"testball_bottle_manifest--2.0.bottle_manifest.json")
        FileUtils.touch pathname_mismatch
        allow(Formulary).to receive(:from_rack).with(HOMEBREW_CELLAR/"testball_bottle_manifest").and_return(nil)
        allow(Formulary).to receive(:from_rack).and_call_original
        allow(Formulary).to receive(:from_rack).with(HOMEBREW_CELLAR/"testball").and_wrap_original do |m, *args|
          formula = m.call(*args)
          if formula
            bottle_double = instance_double(Bottle,
                                            resource: instance_double(Resource, version: Version.new("1.0")),
                                            rebuild:  0)
            allow(formula).to receive(:bottle).and_return(bottle_double)
          end
          formula
        end
        cleanup.cleanup_cache([{ path: pathname_mismatch, type: nil }])
        expect(pathname_mismatch).not_to exist
      end
    end
  end

  describe "::cleanup_python_site_packages" do
    context "when cleaning up Python modules" do
      let(:foo_module) { HOMEBREW_PREFIX/"lib/python3.99/site-packages/foo" }
      let(:foo_pycache) { foo_module/"__pycache__" }
      let(:foo_pyc) { foo_pycache/"foo.cypthon-399.pyc" }

      before do
        foo_pycache.mkpath
        FileUtils.touch foo_pyc
      end

      it "cleans up stray `*.pyc` files" do
        cleanup.cleanup_python_site_packages
        expect(foo_pyc).not_to exist
      end

      it "retains `*.pyc` files of installed modules" do
        FileUtils.touch foo_module/"__init__.py"

        cleanup.cleanup_python_site_packages
        expect(foo_pyc).to exist
      end
    end

    it "cleans up stale `*.pyc` files in the top-level `__pycache__`" do
      pycache = HOMEBREW_PREFIX/"lib/python3.99/site-packages/__pycache__"
      foo_pyc = pycache/"foo.cypthon-3.99.pyc"
      pycache.mkpath
      FileUtils.touch foo_pyc

      allow_any_instance_of(Pathname).to receive(:ctime).and_return(Time.now - (2 * 60 * 60 * 24))
      allow_any_instance_of(Pathname).to receive(:mtime).and_return(Time.now - (2 * 60 * 60 * 24))
      described_class.new(days: 1).cleanup_python_site_packages
      expect(foo_pyc).not_to exist
    end
  end
end
