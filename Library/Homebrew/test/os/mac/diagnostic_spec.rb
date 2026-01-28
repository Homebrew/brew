# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  specify "#check_for_unsupported_macos" do
    ENV.delete("HOMEBREW_DEVELOPER")

    macos_version = MacOSVersion.new("30")
    allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
    allow(OS::Mac.version).to receive_messages(outdated_release?: false, prerelease?: true)

    expect(checks.check_for_unsupported_macos)
      .to match("We do not provide support for this pre-release version.")
  end

  specify "#check_if_xcode_needs_clt_installed" do
    macos_version = MacOSVersion.new("11")
    allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
    allow(OS::Mac::Xcode).to receive_messages(installed?: true, version: "8.0", without_clt?: true)

    expect(checks.check_if_xcode_needs_clt_installed)
      .to match("Xcode alone is not sufficient on Big Sur")
  end

  describe "#check_if_supported_sdk_available" do
    let(:macos_version) { MacOSVersion.new("11") }

    before do
      allow(DevelopmentTools).to receive(:installed?).and_return(true)
      allow(OS::Mac).to receive(:version).and_return(macos_version)
      allow(OS::Mac::CLT).to receive(:below_minimum_version?).and_return(false)
      allow(OS::Mac::Xcode).to receive(:below_minimum_version?).and_return(false)
    end

    it "doesn't trigger when a valid SDK is present" do
      allow(OS::Mac).to receive_messages(sdk: OS::Mac::SDK.new(
        macos_version, "/some/path/MacOSX.sdk", :clt
      ))

      expect(checks.check_if_supported_sdk_available).to be_nil
    end

    it "triggers when a valid SDK is not present on CLT systems" do
      allow(OS::Mac).to receive_messages(sdk: nil, sdk_locator: OS::Mac::CLT.sdk_locator)

      expect(checks.check_if_supported_sdk_available)
        .to include("Your Command Line Tools (CLT) does not support macOS #{macos_version}")
    end

    it "triggers when a valid SDK is not present on Xcode systems" do
      allow(OS::Mac).to receive_messages(sdk: nil, sdk_locator: OS::Mac::Xcode.sdk_locator)

      expect(checks.check_if_supported_sdk_available)
        .to include("Your Xcode does not support macOS #{macos_version}")
    end
  end

  describe "#check_broken_sdks" do
    it "doesn't trigger when SDK versions are as expected" do
      allow(OS::Mac).to receive(:sdk_locator).and_return(OS::Mac::CLT.sdk_locator)
      allow_any_instance_of(OS::Mac::CLTSDKLocator).to receive(:all_sdks).and_return([
        OS::Mac::SDK.new(MacOSVersion.new("11"), "/some/path/MacOSX.sdk", :clt),
        OS::Mac::SDK.new(MacOSVersion.new("10.15"), "/some/path/MacOSX10.15.sdk", :clt),
      ])

      expect(checks.check_broken_sdks).to be_nil
    end

    it "triggers when the CLT SDK version doesn't match the folder name" do
      allow_any_instance_of(OS::Mac::CLTSDKLocator).to receive(:all_sdks).and_return([
        OS::Mac::SDK.new(MacOSVersion.new("10.14"), "/some/path/MacOSX10.15.sdk", :clt),
      ])

      expect(checks.check_broken_sdks)
        .to include("SDKs in your Command Line Tools (CLT) installation do not match the SDK folder names")
    end

    it "triggers when the Xcode SDK version doesn't match the folder name" do
      allow(OS::Mac).to receive(:sdk_locator).and_return(OS::Mac::Xcode.sdk_locator)
      allow_any_instance_of(OS::Mac::XcodeSDKLocator).to receive(:all_sdks).and_return([
        OS::Mac::SDK.new(MacOSVersion.new("10.14"), "/some/path/MacOSX10.15.sdk", :xcode),
      ])

      expect(checks.check_broken_sdks)
        .to include("The contents of the SDKs in your Xcode installation do not match the SDK folder names")
    end
  end

  describe "#check_pkgconf_macos_sdk_mismatch" do
    let(:pkg_config_formula) { instance_double(Formula, any_version_installed?: true) }
    let(:tab) { instance_double(Tab, built_on: { "os_version" => "13" }) }

    before do
      allow(Formulary).to receive(:factory_stub).with("pkgconf").and_return(pkg_config_formula)
      allow(Tab).to receive(:for_formula).with(pkg_config_formula).and_return(tab)
    end

    it "doesn't trigger when pkgconf is not installed" do
      allow(Formulary).to receive(:factory_stub).with("pkgconf").and_raise(FormulaUnavailableError.new("pkgconf"))

      expect(checks.check_pkgconf_macos_sdk_mismatch).to be_nil
    end

    it "doesn't trigger when no versions are installed" do
      allow(pkg_config_formula).to receive(:any_version_installed?).and_return(false)

      expect(checks.check_pkgconf_macos_sdk_mismatch).to be_nil
    end

    it "doesn't trigger when built_on information is missing" do
      allow(tab).to receive(:built_on).and_return(nil)

      expect(checks.check_pkgconf_macos_sdk_mismatch).to be_nil
    end

    it "doesn't trigger when os_version information is missing" do
      allow(tab).to receive(:built_on).and_return({ "cpu_family" => "x86_64" })

      expect(checks.check_pkgconf_macos_sdk_mismatch).to be_nil
    end

    it "doesn't trigger when versions match" do
      current_version = MacOS.version.to_s
      allow(tab).to receive(:built_on).and_return({ "os_version" => current_version })

      expect(checks.check_pkgconf_macos_sdk_mismatch).to be_nil
    end

    it "triggers when built_on version differs from current macOS version" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("14"))
      allow(tab).to receive(:built_on).and_return({ "os_version" => "13" })

      expect(checks.check_pkgconf_macos_sdk_mismatch).to include("brew reinstall pkgconf")
    end
  end

  describe "#check_cask_quarantine_support" do
    it "returns nil when quarantine is available" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:quarantine_available, nil])
      expect(checks.check_cask_quarantine_support).to be_nil
    end

    it "returns error when xattr is broken" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:xattr_broken, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("there's no working version of `xattr` on this system")
    end

    it "returns error when swift is not available" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:no_swift, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("there's no available version of `swift` on this system")
    end

    it "returns error when swift is broken due to missing CLT" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:swift_broken_clt, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("Swift is not working due to missing Command Line Tools")
    end

    it "returns error when swift compilation failed" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:swift_compilation_failed, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("Swift compilation failed")
    end

    it "returns error when swift runtime error occurs" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:swift_runtime_error, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("Swift runtime error")
    end

    it "returns error when swift is not executable" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:swift_not_executable, nil])
      expect(checks.check_cask_quarantine_support)
        .to match("Swift is not executable")
    end

    it "returns error when swift returns unexpected error" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:swift_unexpected_error, "whoopsie"])
      expect(checks.check_cask_quarantine_support)
        .to match("whoopsie")
    end
  end
end
