# frozen_string_literal: true

require "test/support/fixtures/testball"
require "cleanup"
require "cask/cache"
require "fileutils"

RSpec.describe Homebrew::Cleanup do
  subject(:cleanup) { described_class.new }

  let(:ds_store) { Pathname.new("#{HOMEBREW_CELLAR}/.DS_Store") }
  let(:lock_file) { Pathname.new("#{HOMEBREW_LOCKS}/foo") }

  around do |example|
    FileUtils.touch ds_store
    FileUtils.touch lock_file
    FileUtils.mkdir_p HOMEBREW_LIBRARY/"Homebrew/vendor"
    FileUtils.touch HOMEBREW_LIBRARY/"Homebrew/vendor/portable-ruby-version"

    example.run
  ensure
    FileUtils.rm_f ds_store
    FileUtils.rm_f lock_file
    FileUtils.rm_rf HOMEBREW_LIBRARY/"Homebrew"
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

    it "doesn't remove the lock file if it is locked" do
      lock_file.open(File::RDWR | File::CREAT).flock(File::LOCK_EX | File::LOCK_NB)

      cleanup.clean!

      expect(lock_file).to exist
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

      it "does not remove downloads for the latest version" do
        download = Cask::Cache.path/"#{cask.token}--#{cask.version}"

        FileUtils.touch download

        cleanup.cleanup_cask(cask)

        expect(download).to exist
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
    end
  end

  describe "::cleanup_logs" do
    let(:path) { (HOMEBREW_LOGS/"delete_me") }

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

  describe "::cleanup_cache" do
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

    it "cleans up 'npm_cache'" do
      npm_cache = (HOMEBREW_CACHE/"npm_cache")
      npm_cache.mkpath

      cleanup.cleanup_cache

      expect(npm_cache).not_to exist
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

    context "when cleaning old files in HOMEBREW_CACHE" do
      let(:bottle) { (HOMEBREW_CACHE/"testball--0.0.1.tag.bottle.tar.gz") }
      let(:testball) { (HOMEBREW_CACHE/"testball--0.0.1") }
      let(:testball_resource) { (HOMEBREW_CACHE/"testball--rsrc--0.0.1.txt") }

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
  end

  describe "::cleanup_python_site_packages" do
    context "when cleaning up Python modules" do
      let(:foo_module) { (HOMEBREW_PREFIX/"lib/python3.99/site-packages/foo") }
      let(:foo_pycache) { (foo_module/"__pycache__") }
      let(:foo_pyc) { (foo_pycache/"foo.cypthon-399.pyc") }

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
