# typed: true
# frozen_string_literal: true

require "locale"
require "os/mac"

RSpec.describe OS::Mac do
  let(:klass) { OS::Mac }

  describe "::languages" do
    it "returns a list of all languages" do
      expect(klass.languages).not_to be_empty
    end
  end

  describe "::language" do
    it "returns the first item from #languages" do
      expect(klass.language).to eq(klass.languages.first)
    end
  end

  describe "::sdk_path" do
    let(:clt_sdk_path) { Pathname("/tmp/clt/MacOS.sdk") }
    let(:clt_sdk) { OS::Mac::SDK.new(MacOSVersion.new("26"), clt_sdk_path, :clt) }
    let(:xcode_sdk_path) { Pathname("/tmp/xcode/MacOS.sdk") }
    let(:xcode_sdk) { OS::Mac::SDK.new(MacOSVersion.new("26"), xcode_sdk_path, :xcode) }

    before do
      allow_any_instance_of(OS::Mac::CLTSDKLocator).to receive(:sdk_if_applicable).and_return(clt_sdk)
      allow_any_instance_of(OS::Mac::XcodeSDKLocator).to receive(:sdk_if_applicable).and_return(xcode_sdk)
    end

    it "returns the Xcode SDK path on Xcode-only systems" do
      allow(OS::Mac::Xcode).to receive(:installed?).and_return(true)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(false)
      expect(klass.sdk_path).to eq(xcode_sdk_path)
    end

    it "returns the CLT SDK path on CLT-only systems" do
      allow(OS::Mac::Xcode).to receive(:installed?).and_return(false)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(true)
      expect(klass.sdk_path).to eq(clt_sdk_path)
    end
  end
end
