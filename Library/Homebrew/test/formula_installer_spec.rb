# frozen_string_literal: true

require "formula"
require "formula_installer"
require "keg"
require "sandbox"
require "tab"
require "cmd/install"
require "test/support/fixtures/testball"
require "test/support/fixtures/testball_bottle"
require "test/support/fixtures/failball"
require "test/support/fixtures/failball_offline_install"

RSpec.describe FormulaInstaller do
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
      expect(keg.tab).not_to be_poured_from_bottle

      yield formula if block_given?
    ensure
      Tab.clear_cache
      keg.unlink
      keg.uninstall
      formula.clear_cache
      # there will be log files when sandbox is enable.
      FileUtils.rm_r(formula.logs) if formula.logs.directory?
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

  specify "offline installation" do
    expect { temporary_install(FailballOfflineInstall.new) }.to raise_error(BuildError) if Sandbox.available?
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
      dep_path = CoreTap.instance.new_formula_path(dep_name)
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
      formula1_path = CoreTap.instance.new_formula_path(formula1_name)
      formula1_path.write <<~RUBY
        class #{Formulary.class_s(formula1_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{formula2_name}"
        end
      RUBY
      Formulary.cache.delete(formula1_path)
      formula1 = Formulary.factory(formula1_name)

      formula2_path = CoreTap.instance.new_formula_path(formula2_name)
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
      dep_path = CoreTap.instance.new_formula_path(dep_name)
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

  describe "#forbidden_license_check" do
    it "raises on forbidden license on formula" do
      ENV["HOMEBREW_FORBIDDEN_LICENSES"] = "AGPL-3.0"

      f_name = "homebrew-forbidden-license"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
          license "AGPL-3.0"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_license_check
      end.to raise_error(CannotInstallFormulaError, /#{f_name}'s licenses are all forbidden/)
    end

    it "raises on forbidden license on formula with contact instructions" do
      ENV["HOMEBREW_FORBIDDEN_LICENSES"] = "AGPL-3.0"
      ENV["HOMEBREW_FORBIDDEN_OWNER"] = owner = "your dog"
      ENV["HOMEBREW_FORBIDDEN_OWNER_CONTACT"] = contact = "Woof loudly to get this unblocked."

      f_name = "homebrew-forbidden-license"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
          license "AGPL-3.0"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_license_check
      end.to raise_error(CannotInstallFormulaError, /#{owner}.+\n#{contact}/m)
    end

    it "raises on forbidden license on dependency" do
      ENV["HOMEBREW_FORBIDDEN_LICENSES"] = "GPL-3.0"

      dep_name = "homebrew-forbidden-dependency-license"
      dep_path = CoreTap.instance.new_formula_path(dep_name)
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
          license "GPL-3.0"
        end
      RUBY
      Formulary.cache.delete(dep_path)

      f_name = "homebrew-forbidden-dependent-license"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{dep_name}"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_license_check
      end.to raise_error(CannotInstallFormulaError, /dependency on #{dep_name} where all/)
    end
  end

  describe "#forbidden_tap_check" do
    before do
      allow(Tap).to receive_messages(allowed_taps: allowed_taps_set, forbidden_taps: forbidden_taps_set)
    end

    let(:homebrew_forbidden) { Tap.fetch("homebrew/forbidden") }
    let(:allowed_third_party) { Tap.fetch("nothomebrew/allowed") }
    let(:disallowed_third_party) { Tap.fetch("nothomebrew/notallowed") }
    let(:allowed_taps_set) { Set.new([allowed_third_party]) }
    let(:forbidden_taps_set) { Set.new([homebrew_forbidden]) }

    it "raises on forbidden tap on formula" do
      f_tap = homebrew_forbidden
      f_name = "homebrew-forbidden-tap"
      f_path = homebrew_forbidden.new_formula_path(f_name)
      f_path.parent.mkpath
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory("#{f_tap}/#{f_name}")
      fi = described_class.new(f)

      expect do
        fi.forbidden_tap_check
      end.to raise_error(CannotInstallFormulaError, /has the tap #{f_tap}/)
    ensure
      FileUtils.rm_r(f_path.parent.parent)
    end

    it "raises on not allowed third-party tap on formula" do
      f_tap = disallowed_third_party
      f_name = "homebrew-not-allowed-tap"
      f_path = disallowed_third_party.new_formula_path(f_name)
      f_path.parent.mkpath
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory("#{f_tap}/#{f_name}")
      fi = described_class.new(f)

      expect do
        fi.forbidden_tap_check
      end.to raise_error(CannotInstallFormulaError, /has the tap #{f_tap}/)
    ensure
      FileUtils.rm_r(f_path.parent.parent.parent)
    end

    it "does not raise on allowed tap on formula" do
      f_tap = allowed_third_party
      f_name = "homebrew-allowed-tap"
      f_path = allowed_third_party.new_formula_path(f_name)
      f_path.parent.mkpath
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory("#{f_tap}/#{f_name}")
      fi = described_class.new(f)

      expect { fi.forbidden_tap_check }.not_to raise_error
    ensure
      FileUtils.rm_r(f_path.parent.parent.parent)
    end

    it "raises on forbidden tap on dependency" do
      dep_tap = homebrew_forbidden
      dep_name = "homebrew-forbidden-dependency-tap"
      dep_path = homebrew_forbidden.new_formula_path(dep_name)
      dep_path.parent.mkpath
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(dep_path)

      f_name = "homebrew-forbidden-dependent-tap"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{dep_name}"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_tap_check
      end.to raise_error(CannotInstallFormulaError, /from the #{dep_tap} tap but/)
    ensure
      FileUtils.rm_r(dep_path.parent.parent)
    end
  end

  describe "#forbidden_formula_check" do
    it "raises on forbidden formula" do
      ENV["HOMEBREW_FORBIDDEN_FORMULAE"] = f_name = "homebrew-forbidden-formula"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_formula_check
      end.to raise_error(CannotInstallFormulaError, /#{f_name} was forbidden/)
    end

    it "raises on forbidden dependency" do
      ENV["HOMEBREW_FORBIDDEN_FORMULAE"] = dep_name = "homebrew-forbidden-dependency-formula"
      dep_path = CoreTap.instance.new_formula_path(dep_name)
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY
      Formulary.cache.delete(dep_path)

      f_name = "homebrew-forbidden-dependent-formula"
      f_path = CoreTap.instance.new_formula_path(f_name)
      f_path.write <<~RUBY
        class #{Formulary.class_s(f_name)} < Formula
          url "foo"
          version "0.1"
          depends_on "#{dep_name}"
        end
      RUBY
      Formulary.cache.delete(f_path)

      f = Formulary.factory(f_name)
      fi = described_class.new(f)

      expect do
        fi.forbidden_formula_check
      end.to raise_error(CannotInstallFormulaError, /#{dep_name} formula was forbidden/)
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
    it "works if service is set" do
      formula = Testball.new
      service = Homebrew::Service.new(formula)
      launchd_service_path = formula.launchd_service_path
      service_path = formula.systemd_service_path
      formula.opt_prefix.mkpath

      expect(formula).to receive(:service?).and_return(true)
      expect(formula).to receive(:service).at_least(:once).and_return(service)
      expect(formula).to receive(:launchd_service_path).and_call_original
      expect(formula).to receive(:systemd_service_path).and_call_original

      expect(service).to receive(:timed?).and_return(false)
      expect(service).to receive(:command?).and_return(true)
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

      expect(formula).to receive(:service?).and_return(true)
      expect(formula).to receive(:service).at_least(:once).and_return(service)
      expect(formula).to receive(:launchd_service_path).and_call_original
      expect(formula).to receive(:systemd_service_path).and_call_original
      expect(formula).to receive(:systemd_timer_path).and_call_original

      expect(service).to receive(:timed?).and_return(true)
      expect(service).to receive(:command?).and_return(true)
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

      expect(formula).to receive(:service?).and_return(nil)
      expect(formula).not_to receive(:launchd_service_path)

      installer = described_class.new(formula)
      expect do
        installer.install_service
      end.not_to output(/Error: Failed to install service files/).to_stderr

      expect(path).not_to exist
    end
  end
end
