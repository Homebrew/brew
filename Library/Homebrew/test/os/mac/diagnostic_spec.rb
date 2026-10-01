# typed: true
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  describe "#check_for_unsupported_macos" do
    before do
      ENV.delete("HOMEBREW_DEVELOPER")
    end

    it "reports Tier 2 for a pre-release macOS version on Apple Silicon" do
      macos_version = MacOSVersion.new("30")
      allow(Hardware::CPU).to receive(:intel?).and_return(false)
      allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
      allow(OS::Mac.version).to receive_messages(outdated_release?: false, prerelease?: true)

      finding = checks.check_for_unsupported_macos
      expect(finding).to have_attributes(
        tier: 2,
        text: match("We do not provide support for this pre-release version."),
      )
    end

    it "reports Tier 3 on Intel macOS" do
      macos_version = MacOSVersion.new("26")
      allow(Hardware::CPU).to receive(:intel?).and_return(true)
      allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
      allow(OS::Mac.version).to receive_messages(outdated_release?: false, prerelease?: false)

      expect(checks.check_for_unsupported_macos).to have_attributes(
        tier:        3,
        text:        match("We do not provide support for this platform"),
        remediation: have_attributes(text: <<~EOS),
          Homebrew no longer builds bottles for this configuration.
          Existing bottles may still work, but updated formulae may build from source.
        EOS
      )
    end

    it "preserves the remediation for outdated macOS on Intel" do
      macos_version = MacOSVersion.new("13")
      allow(Hardware::CPU).to receive(:intel?).and_return(true)
      allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
      allow(OS::Mac.version).to receive_messages(outdated_release?: true, prerelease?: false)

      finding = checks.check_for_unsupported_macos
      expect(finding).to have_attributes(
        tier:        3,
        text:        include("We (and Apple) do not provide support for this old version."),
        remediation: have_attributes(text: include("MacPorts")),
      )
    end
  end

  specify "#check_if_xcode_needs_clt_installed" do
    macos_version = MacOSVersion.new("11")
    allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
    allow(OS::Mac::Xcode).to receive_messages(installed?: true, version: "8.0", without_clt?: true)

    expect(checks.check_if_xcode_needs_clt_installed&.to_s)
      .to match("Xcode alone is not sufficient on Big Sur")
  end

  describe "#check_xcode_license_approved" do
    it "returns a finding when the Xcode licence is unaccepted" do
      system "false"
      allow(Utils).to receive(:popen_read_text)
        .with("/usr/bin/xcrun", "--find", "clang", err: :out)
        .and_return("You have not agreed to the Xcode license agreements.")

      expect(checks.check_xcode_license_approved&.to_s).to include("You have not agreed to the Xcode license.")
    end
  end

  describe "#fatal_preinstall_checks" do
    it "doesn't require developer tools on Apple Silicon" do
      allow(Hardware::CPU).to receive(:arm?).and_return(true)

      expect(checks.fatal_preinstall_checks).not_to include("check_for_installed_developer_tools")
    end

    it "requires developer tools on Intel" do
      allow(Hardware::CPU).to receive(:arm?).and_return(false)

      expect(checks.fatal_preinstall_checks).to include("check_for_installed_developer_tools")
    end
  end

  describe "#fatal_build_from_source_checks" do
    it "requires developer tools" do
      expect(checks.fatal_build_from_source_checks).to include("check_for_installed_developer_tools")
    end
  end

  describe "#build_from_source_checks" do
    it "warns about missing developer tools" do
      expect(checks.build_from_source_checks).to include("check_for_installed_developer_tools")
    end
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

      expect(checks.check_if_supported_sdk_available&.to_s).to be_nil
    end

    it "triggers when a valid SDK is not present on CLT systems" do
      allow(OS::Mac).to receive_messages(sdk: nil, sdk_locator: OS::Mac::CLT.sdk_locator)

      expect(checks.check_if_supported_sdk_available&.to_s)
        .to include("Your Command Line Tools (CLT) does not support macOS #{macos_version}")
    end

    it "triggers when a valid SDK is not present on Xcode systems" do
      allow(OS::Mac).to receive_messages(sdk: nil, sdk_locator: OS::Mac::Xcode.sdk_locator)

      expect(checks.check_if_supported_sdk_available&.to_s)
        .to include("Your Xcode does not support macOS #{macos_version}")
    end
  end

  describe "#check_pkgconf_macos_sdk_mismatch" do
    let(:pkg_config_formula) { instance_double(Formula, any_version_installed?: true) }
    let(:tab) { instance_double(Tab, built_on: { "os_version" => "13" }) }

    before do
      allow(Formula).to receive(:[]).with("pkgconf").and_return(pkg_config_formula)
      allow(Tab).to receive(:for_formula).with(pkg_config_formula).and_return(tab)
    end

    it "doesn't trigger when pkgconf is not installed" do
      allow(Formula).to receive(:[]).with("pkgconf").and_raise(FormulaUnavailableError.new("pkgconf"))

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "doesn't trigger when no versions are installed" do
      allow(pkg_config_formula).to receive(:any_version_installed?).and_return(false)

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "doesn't trigger when built_on information is missing" do
      allow(tab).to receive(:built_on).and_return(nil)

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "doesn't trigger when os_version information is missing" do
      allow(tab).to receive(:built_on).and_return({ "cpu_family" => "x86_64" })

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "doesn't trigger when versions match" do
      current_version = MacOS.version.to_s
      allow(tab).to receive(:built_on).and_return({ "os_version" => current_version })

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "doesn't trigger when the same major version has a different minor version" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("15.2"))
      allow(tab).to receive(:built_on).and_return({ "os_version" => "15.1" })

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to be_nil
    end

    it "triggers when built_on version differs from current macOS version" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("15"))
      allow(tab).to receive(:built_on).and_return({ "os_version" => "14" })

      expect(checks.check_pkgconf_macos_sdk_mismatch&.to_s).to include("brew reinstall pkgconf")
    end
  end

  describe "#check_cask_quarantine_support" do
    it "returns nil when quarantine is available" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:quarantine_available, nil])
      expect(checks.check_cask_quarantine_support&.to_s).to be_nil
    end

    it "returns error when xattr is broken" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:xattr_broken, nil])
      expect(checks.check_cask_quarantine_support&.to_s)
        .to match("there's no working version of `xattr` on this system")
    end

    it "returns error for an unknown status" do
      allow(Cask::Quarantine).to receive(:check_quarantine_support).and_return([:unknown, "whoopsie"])
      expect(checks.check_cask_quarantine_support&.to_s)
        .to match("whoopsie")
    end
  end
end
