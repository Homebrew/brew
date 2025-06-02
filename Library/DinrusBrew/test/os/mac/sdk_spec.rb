# frozen_string_literal: true

RSpec.describe OS::Mac::CLTSDKLocator do
  subject(:locator) { described_class.new }

  let(:big_sur_sdk) { OS::Mac::SDK.new(MacOSVersion.new("11"), "/some/path/MacOSX.sdk", :clt) }
  let(:catalina_sdk) { OS::Mac::SDK.new(MacOSVersion.new("10.15"), "/some/path/MacOSX10.15.sdk", :clt) }

  specify "#sdk_for" do
    allow(locator).to receive(:all_sdks).and_return([big_sur_sdk, catalina_sdk])

    expect(locator.sdk_for(MacOSVersion.new("11"))).to eq(big_sur_sdk)
    expect(locator.sdk_for(MacOSVersion.new("10.15"))).to eq(catalina_sdk)
    expect { locator.sdk_for(MacOSVersion.new("10.14")) }.to raise_error(described_class::NoSDKError)
  end

  describe "#sdk_if_applicable" do
    before do
      allow(locator).to receive(:all_sdks).and_return([big_sur_sdk, catalina_sdk])
    end

    it "returns the requested SDK" do
      expect(locator.sdk_if_applicable(MacOSVersion.new("11"))).to eq(big_sur_sdk)
      expect(locator.sdk_if_applicable(MacOSVersion.new("10.15"))).to eq(catalina_sdk)
    end

    it "returns the latest SDK if the requested version is not found" do
      expect(locator.sdk_if_applicable(MacOSVersion.new("10.14"))).to eq(big_sur_sdk)
      expect(locator.sdk_if_applicable(MacOSVersion.new("12"))).to eq(big_sur_sdk)
    end

    it "returns the SDK matching the OS version if no version is specified" do
      allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("10.15"))
      expect(locator.sdk_if_applicable).to eq(catalina_sdk)
    end

    it "returns the latest SDK on older OS versions when there's no matching SDK" do
      allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("10.14"))
      expect(locator.sdk_if_applicable).to eq(big_sur_sdk)
    end

    it "returns nil if the OS is newer than all SDKs" do
      allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("12"))
      expect(locator.sdk_if_applicable).to be_nil
    end
  end

  describe "#all_sdks" do
    let(:big_sur_sdk_prefix) { TEST_FIXTURE_DIR/"sdks/big_sur" }
    let(:mojave_broken_sdk_prefix) { TEST_FIXTURE_DIR/"sdks/mojave_broken" }
    let(:high_sierra_sdk_prefix) { TEST_FIXTURE_DIR/"sdks/high_sierra" }
    let(:malformed_sdk_prefix) { TEST_FIXTURE_DIR/"sdks/malformed" }

    it "reads the SDKSettings.json version of unversioned SDKs folders" do
      allow(locator).to receive(:sdk_prefix).and_return(big_sur_sdk_prefix.to_s)

      sdks = locator.all_sdks
      expect(sdks.count).to eq(1)

      sdk = sdks.first
      expect(sdk.path).to eq(big_sur_sdk_prefix/"MacOSX.sdk")
      expect(sdk.version).to eq(MacOSVersion.new("11"))
      expect(sdk.source).to eq(:clt)
    end

    it "reads the SDKSettings.json version of versioned SDKs folders" do
      allow(locator).to receive(:sdk_prefix).and_return(mojave_broken_sdk_prefix.to_s)

      sdks = locator.all_sdks
      expect(sdks.count).to eq(1)

      sdk = sdks.first
      expect(sdk.path).to eq(mojave_broken_sdk_prefix/"MacOSX10.14.sdk")
      expect(sdk.version).to eq(MacOSVersion.new("10.15"))
      expect(sdk.source).to eq(:clt)
    end

    it "reads the SDKSettings.plist version" do
      allow(locator).to receive(:sdk_prefix).and_return(high_sierra_sdk_prefix.to_s)

      sdks = locator.all_sdks
      expect(sdks.count).to eq(1)

      sdk = sdks.first
      expect(sdk.path).to eq(high_sierra_sdk_prefix/"MacOSX10.13.sdk")
      expect(sdk.version).to eq(MacOSVersion.new("10.13"))
      expect(sdk.source).to eq(:clt)
    end

    it "rejects malformed sdks" do
      allow(locator).to receive(:sdk_prefix).and_return(malformed_sdk_prefix.to_s)

      expect(locator.all_sdks).to be_empty
    end
  end
end
