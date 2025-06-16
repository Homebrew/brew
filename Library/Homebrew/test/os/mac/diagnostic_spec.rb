# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  specify "#check_for_unsupported_macos" do
    ENV.delete("HOMEBREW_DEVELOPER")

    macos_version = MacOSVersion.new("10.14")
    allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
    allow(OS::Mac.version).to receive_messages(outdated_release?: false, prerelease?: true)

    expect(checks.check_for_unsupported_macos)
      .to match("We do not provide support for this pre-release version.")
  end

  specify "#check_if_xcode_needs_clt_installed" do
    macos_version = MacOSVersion.new("10.11")
    allow(OS::Mac).to receive_messages(version: macos_version, full_version: macos_version)
    allow(OS::Mac::Xcode).to receive_messages(installed?: true, version: "8.0", without_clt?: true)

    expect(checks.check_if_xcode_needs_clt_installed)
      .to match("Xcode alone is not sufficient on El Capitan")
  end

  describe "#check_if_supported_sdk_available" do
    let(:macos_version) { MacOSVersion.new("11") }

    before do
      allow(DevelopmentTools).to receive(:installed?).and_return(true)
      allow(OS::Mac).to receive(:version).and_return(macos_version)
      allow(OS::Mac::CLT).to receive(:below_minimum_version?).and_return(false)
      allow(OS::Mac::Xcode).to receive(:below_minimum_version?).and_return(false)
    end

    it "doesn't trigger when SDK root is not needed" do
      allow(OS::Mac).to receive_messages(sdk_root_needed?: false, sdk: nil)

      expect(checks.check_if_supported_sdk_available).to be_nil
    end

    it "doesn't trigger when a valid SDK is present" do
      allow(OS::Mac).to receive_messages(sdk_root_needed?: true,
                                         sdk:              OS::Mac::SDK.new(
                                           macos_version, "/some/path/MacOSX.sdk", :clt
                                         ))

      expect(checks.check_if_supported_sdk_available).to be_nil
    end

    it "triggers when a valid SDK is not present on CLT systems" do
      allow(OS::Mac).to receive_messages(sdk_root_needed?: true, sdk: nil, sdk_locator: OS::Mac::CLT.sdk_locator)

      expect(checks.check_if_supported_sdk_available)
        .to include("Your Command Line Tools (CLT) does not support macOS #{macos_version}")
    end

    it "triggers when a valid SDK is not present on Xcode systems" do
      allow(OS::Mac).to receive_messages(sdk_root_needed?: true, sdk: nil, sdk_locator: OS::Mac::Xcode.sdk_locator)

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
end
