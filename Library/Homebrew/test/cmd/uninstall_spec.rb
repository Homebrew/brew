# typed: strict
# frozen_string_literal: true

require "cmd/uninstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::UninstallCmd do
  it_behaves_like "parseable arguments"

  it "uninstalls a given Formula and Cask path", :cask, :integration_test do
    tap = CoreCaskTap.instance
    cask_file = tap.cask_dir/"l/local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache
    cask = Cask::CaskLoader.from_path(cask_file)
    InstallHelper.stub_cask_installation(cask)
    appdir = Pathname(cask.config.appdir)

    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect(HOMEBREW_CELLAR/"testball").to exist
    expect { brew "uninstall", "--force", "testball" }
      .to output(/Uninstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_CELLAR/"testball").not_to exist

    Dir.chdir(tap.path) do
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
      ENV["HOMEBREW_NO_INSTALL_FROM_API"] = nil
      expect do
        brew "uninstall", "--cask", "local-caffeine",
             "HOMEBREW_CASK_OPTS" => "--appdir=#{appdir}"
      end
        .to output(/Uninstalling Cask local-caffeine/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    expect(appdir/"Caffeine.app").not_to exist
    expect(Cask::Caskroom.cask_installed?("local-caffeine")).to be(false)
  ensure
    FileUtils.rm_rf tap.path if tap
  end

  context "when dry-running an uninstall" do
    it "shows what would be uninstalled without uninstalling" do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      keg_file = keg_path/"bin/testball"
      keg_file.dirname.mkpath
      keg_file.write("")
      link = HOMEBREW_PREFIX/"bin/testball"
      link.dirname.mkpath
      link.make_relative_symlink(keg_file)
      keg = Keg.new(keg_path)
      allow(keg).to receive(:tab).and_return(instance_double(Tab, tap: nil))

      cask = Cask::Cask.new("test-cask")
      allow(cask).to receive(:installed?).and_return(true)
      cmd = described_class.new(["--dry-run", "testball", "test-cask"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([keg, cask])
      allow(Formulary).to receive(:from_rack).with(keg.rack).and_return(instance_double(Formula, pinned?: false))

      expect(Homebrew::Uninstall).to receive(:uninstall_kegs)
        .with({ keg.rack => [keg] }, casks: [cask], force: false, ignore_dependencies: false,
                                     named_args: cmd.args.named, dry_run: true)
        .and_call_original
      expect(keg).to receive(:unlink).with(dry_run: true).and_call_original
      expect(keg).to receive(:uninstall).with(dry_run: true).and_call_original
      expect(Homebrew::Uninstall).to receive(:handle_unsatisfied_dependents)
        .with({ keg.rack => [keg] }, casks: [cask], ignore_dependencies: false, named_args: cmd.args.named)
      expect(Cask::Uninstall).to receive(:check_dependent_casks).with(cask, named_args: cmd.args.named)
      expect(Cask::Uninstall).to receive(:uninstall_casks)
        .with(cask, verbose: false, force: false, dry_run: true)
        .and_call_original
      expect(Homebrew::Cleanup).to receive(:autoremove)
        .with(dry_run: true, removed_kegs: [keg], removed_casks: [cask])

      expect { cmd.run }.to output(<<~EOS).to_stdout
        Would uninstall testball 0.1
        Would uninstall Cask test-cask
      EOS

      expect(keg).to exist
      expect(link).to be_a_symlink
    end

    it "accepts the short dry-run option" do
      cmd = described_class.new(["-n", "testball"])

      expect(cmd.args.dry_run?).to be(true)
    end

    it "reports an error when the requested package does not exist" do
      cmd = described_class.new(["--dry-run", "--formula", "missing-package"])
      error_message = /No such keg: #{Regexp.escape((HOMEBREW_CELLAR/"missing-package").to_s)}/

      expect { cmd.run }
        .to output(error_message).to_stderr
        .and not_to_output.to_stdout

      expect(Homebrew).to have_failed
    ensure
      Homebrew.failed = false
    end

    it "does not show an uninstall plan when formulae have installed dependents" do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      keg_path.mkpath
      keg = Keg.new(keg_path)
      allow(keg).to receive(:tab).and_return(instance_double(Tab, tap: nil))
      cmd = described_class.new(["--dry-run", "testball"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([keg])
      allow(Homebrew::Uninstall).to receive(:handle_unsatisfied_dependents) { Homebrew.failed = true }
      allow(Cask::Uninstall).to receive(:check_dependent_casks)

      expect(Homebrew::Cleanup).not_to receive(:autoremove)

      expect { cmd.run }.not_to output.to_stdout
      expect(Homebrew).to have_failed
    ensure
      Homebrew.failed = false
    end

    it "does not show an uninstalled cask unless forced" do
      cask = Cask::Cask.new("test-cask")
      allow(cask).to receive(:installed?).and_return(false)
      cmd = described_class.new(["--dry-run", "--cask", "test-cask"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])
      allow(Homebrew::Uninstall).to receive(:handle_unsatisfied_dependents)
      allow(Cask::Uninstall).to receive(:check_dependent_casks)

      expect(Homebrew::Cleanup).not_to receive(:autoremove)
      expect { cmd.run }
        .to output(/Cask 'test-cask' is not installed/).to_stderr
        .and not_to_output(/Would uninstall/).to_stdout
      expect(Homebrew).to have_failed
    ensure
      Homebrew.failed = false
    end

    it "does not show pinned formulae or casks unless forced" do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      keg_path.mkpath
      keg = Keg.new(keg_path)
      allow(keg).to receive(:tab).and_return(instance_double(Tab, tap: nil))
      formula = instance_double(Formula, pinned?: true, full_name: "testball")
      allow(Formulary).to receive(:from_rack).with(keg.rack).and_return(formula)

      cask = Cask::Cask.new("test-cask")
      allow(cask).to receive_messages(installed?: true, pinned?: true)
      cmd = described_class.new(["--dry-run", "testball", "test-cask"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([keg, cask])
      allow(Homebrew::Uninstall).to receive(:handle_unsatisfied_dependents)
      allow(Cask::Uninstall).to receive(:check_dependent_casks)

      expect(Cask::Uninstall).to receive(:unpin_for_removal?)
        .with(cask, force: false, dry_run: true).and_call_original
      expect(Homebrew::Cleanup).not_to receive(:autoremove)
      expect { cmd.run }
        .to output(/testball is pinned.*test-cask is pinned/m).to_stderr
        .and not_to_output(/Would uninstall/).to_stdout
    end
  end

  context "when uninstalling a cask" do
    before do
      allow(Cask::Uninstall).to receive(:uninstall_casks)
      allow(Cask::Uninstall).to receive(:check_dependent_casks)
      allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    end

    it "autoremoves by default" do
      cmd = described_class.new(["test-cask"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([Cask::Cask.new("test-cask")])

      expect(Homebrew::Cleanup).to receive(:autoremove)

      cmd.run
    end

    it "doesn't autoremove with `HOMEBREW_NO_AUTOREMOVE`" do
      ENV["HOMEBREW_NO_AUTOREMOVE"] = "1"
      cmd = described_class.new(["test-cask"])
      allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([Cask::Cask.new("test-cask")])

      expect(Homebrew::Cleanup).not_to receive(:autoremove)

      cmd.run
    end
  end

  it "catches cask uninstall errors and sets Homebrew.failed" do
    allow(Cask::Uninstall).to receive(:uninstall_casks).and_raise(Cask::CaskError.new("test cask error"))
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Homebrew::Cleanup).to receive(:autoremove)

    cask = Cask::Cask.new("test-cask")
    cmd = described_class.new(["test-cask"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])

    expect { cmd.run }
      .to output(/test cask error/).to_stderr

    expect(Homebrew).to have_failed
  ensure
    Homebrew.failed = false
  end

  it "untrusts uninstalled casks" do
    cask = Cask::Cask.new("test-cask")
    allow(cask).to receive(:full_name).and_return("thirdparty/foo/test-cask")
    cmd = described_class.new(["thirdparty/foo/test-cask"])
    allow(cmd.args.named).to receive(:to_formulae_and_casks_and_unavailable).and_return([cask])
    allow(Cask::Uninstall).to receive(:check_dependent_casks)
    allow(Cask::Uninstall).to receive(:uninstall_casks)
    allow(Homebrew::Uninstall).to receive(:uninstall_kegs)
    allow(Homebrew::Cleanup).to receive(:autoremove)

    expect(Homebrew::Trust).to receive(:untrust!)
      .with(:cask, "thirdparty/foo/test-cask")

    cmd.run
  end

  it "does not read an untrusted installed cask when uninstalling", :cask, :trust_store do
    tap = Tap.fetch("untrusted", "tap")
    full_name = "untrusted/tap/local-caffeine"
    cask_file = tap.cask_dir/"local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache

    Homebrew::Trust.trust!(:tap, tap)
    cask = Cask::CaskLoader.load(full_name).tap { |loaded_cask| Cask::Installer.new(loaded_cask).install }
    Homebrew::Trust.untrust!(:tap, tap.name)
    cask_file.write <<~RUBY
      raise "untrusted tap cask evaluated"
    RUBY
    installed_caskfile = cask.installed_caskfile
    (installed_caskfile.dirname/"local-caffeine.rb").write <<~RUBY
      raise "untrusted installed cask evaluated"
    RUBY
    installed_caskfile.unlink
    allow(Homebrew::Cleanup).to receive(:autoremove)

    original_argv = ARGV.dup
    begin
      ARGV.replace(["--cask", "--force", full_name])
      expect { described_class.new(["--cask", "--force", full_name]).run }
        .to output(/Uninstalling Cask local-caffeine/).to_stdout
        .and output(/Skipping loading untrusted Cask #{full_name}; uninstalling recorded artifacts only/).to_stderr
        .and not_to_output(/untrusted .* cask evaluated/).to_stderr
    ensure
      ARGV.replace(original_argv)
      FileUtils.rm_rf tap.path.parent
    end

    expect(Pathname(cask.config.appdir).join("Caffeine.app")).not_to exist
    expect(cask).not_to be_installed
  end

  it "reads installed JSON cask metadata when uninstalling from an untrusted tap", :cask, :trust_store do
    tap = Tap.fetch("untrusted", "json")
    full_name = "untrusted/json/local-caffeine"
    cask_file = tap.cask_dir/"local-caffeine.rb"
    cask_file.dirname.mkpath
    FileUtils.cp cask_path("local-caffeine"), cask_file
    tap.clear_cache

    Homebrew::Trust.trust!(:tap, tap)
    cask = Cask::CaskLoader.load(full_name).tap { |loaded_cask| Cask::Installer.new(loaded_cask).install }
    Homebrew::Trust.untrust!(:tap, tap.name)
    cask_file.write <<~RUBY
      raise "untrusted tap cask evaluated"
    RUBY
    (cask.installed_caskfile.dirname/"local-caffeine.rb").write <<~RUBY
      raise "untrusted installed cask evaluated"
    RUBY
    allow(Homebrew::Cleanup).to receive(:autoremove)

    original_argv = ARGV.dup
    begin
      ARGV.replace(["--cask", "--force", full_name])
      expect { described_class.new(["--cask", "--force", full_name]).run }
        .to output(/Uninstalling Cask local-caffeine/).to_stdout
        .and not_to_output(/Skipping loading untrusted Cask/).to_stderr
        .and not_to_output(/untrusted .* cask evaluated/).to_stderr
    ensure
      ARGV.replace(original_argv)
      FileUtils.rm_rf tap.path.parent
    end

    expect(Pathname(cask.config.appdir).join("Caffeine.app")).not_to exist
    expect(cask).not_to be_installed
  end
end
