# typed: strict
# frozen_string_literal: true

require "utils/path"

RSpec.describe Utils::Path do
  describe "inclusion" do
    it "provides private path helpers and public Formula helpers" do
      expect(described_class.private_instance_methods).to include(:resolved_path)
      expect(described_class.public_instance_methods).to include(:formula_opt_bin)
    end
  end

  describe "::child_of?" do
    it "recognizes a path as its own child" do
      expect(described_class.child_of?("/foo/bar", "/foo/bar")).to be(true)
    end

    it "recognizes a path that is a child of the parent" do
      expect(described_class.child_of?("/foo", "/foo/bar")).to be(true)
    end

    it "recognizes a path that is a grandchild of the parent" do
      expect(described_class.child_of?("/foo", "/foo/bar/baz")).to be(true)
    end

    it "does not recognize a path that is not a child" do
      expect(described_class.child_of?("/foo", "/bar/baz")).to be(false)
    end

    it "handles . and .. in paths correctly" do
      expect(described_class.child_of?("/foo", "/foo/./bar")).to be(true)
      expect(described_class.child_of?("/foo/bar", "/foo/../foo/bar/baz")).to be(true)
    end

    it "handles relative paths correctly" do
      expect(described_class.child_of?("foo", "./bar/baz")).to be(false)
      expect(described_class.child_of?("../foo", "./bar/baz/../../../foo/bar/baz")).to be(true)
    end
  end

  describe "::ensure_child_of!" do
    it "allows a path that is a child of the parent" do
      expect { described_class.ensure_child_of!("/foo", "/foo/bar", message: "outside") }.not_to raise_error
    end

    it "raises the provided message for a path that is not a child" do
      expect { described_class.ensure_child_of!("/foo", "/bar/baz", message: "outside") }.to raise_error("outside")
    end

    it "raises for an existing path that reaches outside the parent through a symlink" do
      mktmpdir do |dir|
        (dir/"outside").mkpath
        (dir/"outside/target").write("secret\n")
        (dir/"parent").mkpath
        FileUtils.ln_s(dir/"outside", dir/"parent/link")

        expect { described_class.ensure_child_of!(dir/"parent", dir/"parent/link/target", message: "outside") }
          .to raise_error("outside")
      end
    end

    it "raises for a path that does not exist yet under a symlinked directory" do
      mktmpdir do |dir|
        (dir/"outside").mkpath
        (dir/"parent").mkpath
        FileUtils.ln_s(dir/"outside", dir/"parent/link")

        expect { described_class.ensure_child_of!(dir/"parent", dir/"parent/link/new", message: "outside") }
          .to raise_error("outside")
      end
    end

    it "raises for a dangling symlink, which `exist?` reports as missing" do
      mktmpdir do |dir|
        (dir/"parent").mkpath
        FileUtils.ln_s((dir/"outside/planted").to_s, (dir/"parent/dangle").to_s)

        expect { described_class.ensure_child_of!(dir/"parent", dir/"parent/dangle", message: "outside") }
          .to raise_error("outside")
      end
    end

    it "allows a real path within the parent" do
      mktmpdir do |dir|
        (dir/"parent/src").mkpath

        expect { described_class.ensure_child_of!(dir/"parent", dir/"parent/src/foo.c", message: "outside") }
          .not_to raise_error
      end
    end
  end

  describe "::cp_path_sub" do
    it "copies a file and replaces the given pattern" do
      src = mktmpdir
      dst = mktmpdir
      file = src/"file"
      file.write("content")

      described_class.cp_path_sub(file, src, dst)

      expect((dst/file.basename).read).to eq("content")
    end

    it "creates a directory with the substituted path" do
      src = mktmpdir
      dst = mktmpdir
      dir = src/"dir"
      dir.mkpath

      described_class.cp_path_sub(dir, src, dst)

      expect(dst/dir.basename).to be_a_directory
    end
  end

  describe "::install_info" do
    it "updates the info directory" do
      file = mktmpdir/"file.info"
      allow(described_class).to receive(:install_info_executable).and_return("/usr/bin/install-info")
      expect(SystemCommand).to receive(:quiet_system)
        .with("/usr/bin/install-info", "--quiet", file.to_s, (file.dirname/"dir").to_s)

      described_class.install_info(file)
    end

    it "reports the update when verbose" do
      file = mktmpdir/"file.info"
      allow(described_class).to receive(:install_info_executable).and_return("/usr/bin/install-info")
      allow(SystemCommand).to receive(:quiet_system)

      expect { described_class.install_info(file, verbose: true) }.to output("info #{file}\n").to_stdout
    end
  end

  describe "::uninstall_info" do
    it "removes an entry from the info directory" do
      file = mktmpdir/"file.info"
      allow(described_class).to receive(:install_info_executable).and_return("/usr/bin/install-info")
      expect(SystemCommand).to receive(:quiet_system)
        .with("/usr/bin/install-info", "--delete", "--quiet", file.to_s, (file.dirname/"dir").to_s)

      described_class.uninstall_info(file)
    end

    it "reports the update when verbose" do
      file = mktmpdir/"file.info"
      allow(described_class).to receive(:install_info_executable).and_return("/usr/bin/install-info")
      allow(SystemCommand).to receive(:quiet_system)

      expect { described_class.uninstall_info(file, verbose: true) }.to output("uninfo #{file}\n").to_stdout
    end
  end

  describe "::rmdir_if_possible" do
    it "removes an empty directory" do
      dir = mktmpdir

      expect(described_class.rmdir_if_possible(dir)).to be(true)
      expect(dir).not_to exist
    end

    it "does not remove a directory containing files" do
      dir = mktmpdir
      (dir/"file").write("content")

      expect(described_class.rmdir_if_possible(dir)).to be(false)
      expect(dir).to be_a_directory
    end

    it "ignores a .DS_Store file" do
      dir = mktmpdir
      (dir/".DS_Store").write("")

      expect(described_class.rmdir_if_possible(dir)).to be(true)
      expect(dir).not_to exist
    end
  end

  describe "::text_executable?" do
    it "detects a shebang" do
      file = mktmpdir/"script"
      file.write("#!/bin/sh\necho Homebrew\n")

      expect(described_class.text_executable?(file)).to be(true)
    end
  end

  describe "::resolved_path" do
    it "returns a symlink target" do
      dir = mktmpdir
      target = dir/"target"
      target.write("")
      link = dir/"link"
      FileUtils.ln_s(target.basename, link)

      expect(described_class.resolved_path(link)).to eq(target)
    end
  end

  describe "::resolved_path_exists?" do
    it "returns whether a symlink target exists" do
      dir = mktmpdir
      target = dir/"target"
      link = dir/"link"
      FileUtils.ln_s(target.basename, link)

      expect(described_class.resolved_path_exists?(link)).to be(false)
      target.write("")
      expect(described_class.resolved_path_exists?(link)).to be(true)
    end
  end

  describe "::ensure_writable" do
    it "makes a file writable and restores its permissions" do
      skip "User is root so everything is writable." if Process.euid.zero?

      file = mktmpdir/"file"
      file.write("")
      file.chmod(0555)

      described_class.ensure_writable(file) { expect(file).to be_writable }
      expect(file).not_to be_writable
    end
  end

  describe "::formula_opt_prefix" do
    it "returns a formula opt prefix without loading a Formula object" do
      expect(described_class.formula_opt_prefix("foo")).to eq(HOMEBREW_PREFIX/"opt/foo")
    end

    it "returns a formula opt prefix for a fully qualified formula name" do
      expect(described_class.formula_opt_prefix("homebrew/core/foo")).to eq(HOMEBREW_PREFIX/"opt/foo")
    end
  end

  describe "::formula_opt_bin" do
    it "returns a formula opt bin path without loading a Formula object" do
      expect(described_class.formula_opt_bin("foo")).to eq(HOMEBREW_PREFIX/"opt/foo/bin")
    end
  end

  describe "::formula_opt_lib" do
    it "returns a formula opt lib path without loading a Formula object" do
      expect(described_class.formula_opt_lib("foo")).to eq(HOMEBREW_PREFIX/"opt/foo/lib")
    end
  end

  describe "::formula_opt_libexec" do
    it "returns a formula opt libexec path without loading a Formula object" do
      expect(described_class.formula_opt_libexec("foo")).to eq(HOMEBREW_PREFIX/"opt/foo/libexec")
    end
  end

  describe "::formula_opt_include" do
    it "returns a formula opt include path without loading a Formula object" do
      expect(described_class.formula_opt_include("foo")).to eq(HOMEBREW_PREFIX/"opt/foo/include")
    end
  end

  describe "::formula_installed_prefixes" do
    it "returns installed prefixes for formula names" do
      tmpdir = mktmpdir
      stub_const("HOMEBREW_CELLAR", tmpdir)
      (tmpdir/"old-foo/1.0").mkpath
      (tmpdir/"foo/2.0").mkpath

      expect(described_class.formula_installed_prefixes(["foo", "old-foo"]))
        .to eq([tmpdir/"old-foo/1.0", tmpdir/"foo/2.0"])
    end

    it "does not list kegs twice when a name is a symlink to another rack" do
      tmpdir = mktmpdir
      stub_const("HOMEBREW_CELLAR", tmpdir)
      (tmpdir/"foo/1.0").mkpath
      FileUtils.ln_s(tmpdir/"foo", tmpdir/"foo-alias")

      expect(described_class.formula_installed_prefixes(["foo", "foo-alias"]))
        .to eq([tmpdir/"foo/1.0"])
    end
  end

  describe "::formula_any_version_installed?" do
    it "checks whether any formula keg has an install receipt without loading a Formula object" do
      tmpdir = mktmpdir
      stub_const("HOMEBREW_CELLAR", tmpdir)
      expect(described_class.formula_any_version_installed?("foo")).to be(false)

      (tmpdir/"foo/1.0").mkpath
      expect(described_class.formula_any_version_installed?("foo")).to be(false)

      (tmpdir/"foo/1.0/INSTALL_RECEIPT.json").write("{}")
      expect(described_class.formula_any_version_installed?("foo")).to be(true)
    end

    it "checks fully qualified formula names" do
      tmpdir = mktmpdir
      stub_const("HOMEBREW_CELLAR", tmpdir)
      (tmpdir/"foo/1.0/INSTALL_RECEIPT.json").tap do |receipt|
        receipt.dirname.mkpath
        receipt.write("{}")
      end

      expect(described_class.formula_any_version_installed?("homebrew/core/foo")).to be(true)
    end

    it "checks multiple possible formula names" do
      tmpdir = mktmpdir
      stub_const("HOMEBREW_CELLAR", tmpdir)
      (tmpdir/"old-foo/1.0/INSTALL_RECEIPT.json").tap do |receipt|
        receipt.dirname.mkpath
        receipt.write("{}")
      end

      expect(described_class.formula_any_version_installed?(["foo", "old-foo"])).to be(true)
    end
  end

  describe "::formula_opt_bin_path" do
    it "prepends a formula opt bin path to the current PATH by default" do
      expect(described_class.formula_opt_bin_path("foo")).to eq(PATH.new(HOMEBREW_PREFIX/"opt/foo/bin",
                                                                         ENV.fetch("PATH")))
    end

    it "prepends a formula opt bin path to PATH entries" do
      expect(described_class.formula_opt_bin_path("foo", "/usr/bin")).to eq(PATH.new(HOMEBREW_PREFIX/"opt/foo/bin",
                                                                                     "/usr/bin",
                                                                                     ENV.fetch("PATH")))
    end
  end

  describe "::formula_opt_bin_env" do
    it "returns a PATH environment with a formula opt bin path prepended to the current PATH by default" do
      expect(described_class.formula_opt_bin_env("foo"))
        .to eq({ "PATH" => PATH.new(HOMEBREW_PREFIX/"opt/foo/bin", ENV.fetch("PATH")).to_s })
    end

    it "returns a PATH environment with extra PATH entries" do
      expect(described_class.formula_opt_bin_env("foo", "/usr/bin"))
        .to eq({ "PATH" => PATH.new(HOMEBREW_PREFIX/"opt/foo/bin", "/usr/bin", ENV.fetch("PATH")).to_s })
    end
  end

  describe "::loadable_package_path?" do
    it "accepts formula paths under a symlinked cellar" do
      tmpdir = mktmpdir
      real_cellar = tmpdir/"real-cellar"
      symlink_cellar = tmpdir/"cellar"

      real_cellar.mkpath
      FileUtils.ln_s(real_cellar, symlink_cellar)
      stub_const("HOMEBREW_CELLAR", symlink_cellar)
      allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(true)

      formula_path = real_cellar/"poshtui/0.16/.brew/poshtui.rb"
      formula_path.dirname.mkpath
      formula_path.write <<~RUBY
        class Poshtui < Formula; end
      RUBY

      expect(described_class.loadable_package_path?(formula_path, :formula)).to be(true)
    end

    it "accepts formula paths under a symlinked tap" do
      tmpdir = mktmpdir.realpath
      library = tmpdir/"Library"
      (library/"Taps/homebrew").mkpath
      stub_const("HOMEBREW_LIBRARY", library)
      allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(true)

      external_tap = tmpdir/"external/homebrew-foo"
      (external_tap/"Formula").mkpath
      FileUtils.ln_s(external_tap, library/"Taps/homebrew/homebrew-foo")

      formula_path = library/"Taps/homebrew/homebrew-foo/Formula/foo.rb"
      formula_path.write "class Foo < Formula; end\n"

      expect(described_class.loadable_package_path?(formula_path, :formula)).to be(true)
    end

    it "rejects formula paths that escape a trusted root via `..` segments" do
      tmpdir = mktmpdir.realpath
      library = tmpdir/"Library"
      (library/"Taps").mkpath
      stub_const("HOMEBREW_LIBRARY", library)
      allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(true)

      escaped = tmpdir/"evil.rb"
      escaped.write "class Evil < Formula; end\n"

      # Textually starts under `Taps/` but resolves to `tmpdir/evil.rb` outside it.
      traversal_path = library/"Taps/../../evil.rb"

      expect { described_class.loadable_package_path?(traversal_path, :formula) }
        .to raise_error(/to be in a tap/)
    end

    it "rejects local JSON cask paths" do
      tmpdir = mktmpdir.realpath
      (tmpdir/"Library/Taps").mkpath
      stub_const("HOMEBREW_LIBRARY", tmpdir/"Library")
      allow(Homebrew::EnvConfig).to receive(:forbid_packages_from_paths?).and_return(true)

      cask_path = tmpdir/"evil.json"
      cask_path.write "{}\n"

      expect { described_class.loadable_package_path?(cask_path, :cask) }
        .to raise_error(/to be in a tap/)
    end
  end
end
