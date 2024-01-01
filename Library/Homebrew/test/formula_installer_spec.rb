# frozen_string_literal: true

require "formula"
require "formula_installer"
require "keg"
require "tab"
require "cmd/install"
require "test/support/fixtures/testball"
require "test/support/fixtures/testball_bottle"
require "test/support/fixtures/failball"

describe FormulaInstaller do
  matcher :be_poured_from_bottle do
    match(&:poured_from_bottle)
  end

  def temporary_install(formula, **options)
    expect(formula).not_to be_latest_version_installed

    installer = described_class.new(formula, **options)

    installer.fetch
    installer.install

    keg = Keg.new(formula.prefix)

    expect(formula).to be_latest_version_installed

    begin
      Tab.clear_cache
      expect(Tab.for_keg(keg)).not_to be_poured_from_bottle

      yield formula if block_given?
    ensure
      Tab.clear_cache
      keg.unlink
      keg.uninstall
      formula.clear_cache
      # there will be log files when sandbox is enable.
      formula.logs.rmtree if formula.logs.directory?
    end

    expect(keg).not_to exist
    expect(formula).not_to be_latest_version_installed
  end

  specify "basic installation" do
    temporary_install(Testball.new) do |f|
      # Test that things made it into the Keg
      # "readme" is empty, so it should not be installed
      expect(f.prefix/"readme").not_to exist

      expect(f.bin).to be_a_directory
      expect(f.bin.children.count).to eq(3)

      expect(f.libexec).to be_a_directory
      expect(f.libexec.children.count).to eq(1)

      expect(f.prefix/"main.c").not_to exist
      expect(f.prefix/"license").not_to exist

      # Test that things make it into the Cellar
      keg = Keg.new f.prefix
      keg.link

      bin = HOMEBREW_PREFIX/"bin"
      expect(bin).to be_a_directory
      expect(bin.children.count).to eq(3)
      expect(f.prefix/".brew/testball.rb").to be_readable
    end
  end

  specify "Formula is not poured from bottle when compiler specified" do
    temporary_install(TestballBottle.new, cc: "clang") do |f|
      tab = Tab.for_formula(f)
      expect(tab.compiler).to eq("clang")
    end
  end

  describe "#check_install_sanity" do
    it "raises on direct cyclic dependency" do
      ENV["HOMEBREW_DEVELOPER"] = "1"

      dep_name = "homebrew-test-cyclic"
      dep_path = CoreTap.new.new_formula_path(dep_name)
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{dep_name}"
        end
      RUBY
      Formulary.cache.delete(dep_path)
      f = Formulary.factory(dep_name)

      fi = described_class.new(f)

      expect do
        fi.check_install_sanity
      end.to raise_error(CannotInstallFormulaError)
    end

    it "raises on indirect cyclic dependency" do
      ENV["HOMEBREW_DEVELOPER"] = "1"

      formula1_name = "homebrew-test-formula1"
      formula2_name = "homebrew-test-formula2"
      formula1_path = CoreTap.new.new_formula_path(formula1_name)
      formula1_path.write <<~RUBY
        class #{Formulary.class_s(formula1_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{formula2_name}"
        end
      RUBY
      Formulary.cache.delete(formula1_path)
      formula1 = Formulary.factory(formula1_name)

      formula2_path = CoreTap.new.new_formula_path(formula2_name)
      formula2_path.write <<~RUBY
        class #{Formulary.class_s(formula2_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{formula1_name}"
        end
      RUBY
      Formulary.cache.delete(formula2_path)

      fi = described_class.new(formula1)

      expect do
        fi.check_install_sanity
      end.to raise_error(CannotInstallFormulaError)
    end

    it "raises on pinned dependency" do
      dep_name = "homebrew-test-dependency"
      dep_path = CoreTap.new.new_formula_path(dep_name)
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.2"
        end
      RUBY

      Formulary.cache.delete(dep_path)
      dependency = Formulary.factory(dep_name)

      dependent = formula do
        url "foo"
        version "0.5"
        depends_on dependency.name.to_s
      end

      (dependency.prefix("0.1")/"bin"/"a").mkpath
      HOMEBREW_PINNED_KEGS.mkpath
      FileUtils.ln_s dependency.prefix("0.1"), HOMEBREW_PINNED_KEGS/dep_name

      dependency_keg = Keg.new(dependency.prefix("0.1"))
      dependency_keg.link

      expect(dependency_keg).to be_linked
      expect(dependency).to be_pinned

      fi = described_class.new(dependent)

      expect do
        fi.check_install_sanity
      end.to raise_error(CannotInstallFormulaError)
    end
  end

  specify "install fails with BuildError when a system() call fails" do
    ENV["HOMEBREW_TEST_NO_EXIT_CLEANUP"] = "1"
    ENV["FAILBALL_BUILD_ERROR"] = "1"

    expect do
      temporary_install(Failball.new)
    end.to raise_error(BuildError)
  end

  specify "install fails with a RuntimeError when #install raises" do
    ENV["HOMEBREW_TEST_NO_EXIT_CLEANUP"] = "1"

    expect do
      temporary_install(Failball.new)
    end.to raise_error(RuntimeError)
  end

  describe "#caveats" do
    subject(:formula_installer) { described_class.new(Testball.new) }

    it "shows audit problems if HOMEBREW_DEVELOPER is set" do
      ENV["HOMEBREW_DEVELOPER"] = "1"
      formula_installer.fetch
      formula_installer.install
      expect(formula_installer).to receive(:audit_installed).and_call_original
      formula_installer.caveats
    end
  end

  describe "#install_service" do
    it "works if plist is set" do
      formula = Testball.new
      path = formula.launchd_service_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:plist).twice.and_return("PLIST")
      expect(formula).to receive(:launchd_service_path).and_call_original

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.not_to output(/Error: Failed to install service files/).to_stderr

      expect(path).to exist
    end

    it "works if service is set" do
      formula = Testball.new
      service = Homebrew::Service.new(formula)
      launchd_service_path = formula.launchd_service_path
      service_path = formula.systemd_service_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:plist).and_return(nil)
      expect(formula).to receive(:service?).exactly(3).and_return(true)
      expect(formula).to receive(:service).exactly(7).and_return(service)
      expect(formula).to receive(:launchd_service_path).and_call_original
      expect(formula).to receive(:systemd_service_path).and_call_original

      expect(service).to receive(:timed?).and_return(false)
      expect(service).to receive(:command?).exactly(2).and_return(true)
      expect(service).to receive(:to_plist).and_return("plist")
      expect(service).to receive(:to_systemd_unit).and_return("unit")

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.not_to output(/Error: Failed to install service files/).to_stderr

      expect(launchd_service_path).to exist
      expect(service_path).to exist
    end

    it "works if timed service is set" do
      formula = Testball.new
      service = Homebrew::Service.new(formula)
      launchd_service_path = formula.launchd_service_path
      service_path = formula.systemd_service_path
      timer_path = formula.systemd_timer_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:plist).and_return(nil)
      expect(formula).to receive(:service?).exactly(3).and_return(true)
      expect(formula).to receive(:service).exactly(9).and_return(service)
      expect(formula).to receive(:launchd_service_path).and_call_original
      expect(formula).to receive(:systemd_service_path).and_call_original
      expect(formula).to receive(:systemd_timer_path).and_call_original

      expect(service).to receive(:timed?).and_return(true)
      expect(service).to receive(:command?).exactly(2).and_return(true)
      expect(service).to receive(:to_plist).and_return("plist")
      expect(service).to receive(:to_systemd_unit).and_return("unit")
      expect(service).to receive(:to_systemd_timer).and_return("timer")

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.not_to output(/Error: Failed to install service files/).to_stderr

      expect(launchd_service_path).to exist
      expect(service_path).to exist
      expect(timer_path).to exist
    end

    it "returns without definition" do
      formula = Testball.new
      path = formula.launchd_service_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:plist).and_return(nil)
      expect(formula).to receive(:service?).exactly(3).and_return(nil)
      expect(formula).not_to receive(:launchd_service_path)
      expect(formula).not_to receive(:to_systemd_unit)

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.not_to output(/Error: Failed to install service files/).to_stderr

      expect(path).not_to exist
    end

    it "errors with duplicate definition" do
      formula = Testball.new
      path = formula.launchd_service_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:plist).and_return("plist")
      expect(formula).to receive(:service?).and_return(true)
      expect(formula).not_to receive(:service)
      expect(formula).not_to receive(:launchd_service_path)

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.to output("Error: Formula specified both service and plist\n").to_stderr

      expect(Homebrew).to have_failed
      expect(path).not_to exist
    end
  end
end
