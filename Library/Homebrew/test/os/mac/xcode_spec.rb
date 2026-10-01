# typed: strict
# frozen_string_literal: true

require "os/mac/xcode"

RSpec.describe OS::Mac::Xcode, :needs_macos do
  describe ".latest_version" do
    it "returns the Xcode version for Golden Gate" do
      expect(described_class.latest_version(macos: MacOSVersion.new("27"))).to eq("27.0")
    end

    it "returns Xcode 26.6 for Tahoe" do
      expect(described_class.latest_version(macos: MacOSVersion.new("26"))).to eq("26.6")
    end
  end

  describe ".detect_version" do
    it "infers Xcode 27 from the Command Line Tools compiler" do
      allow(described_class).to receive_messages(installed?: false, prefix: nil)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(true)
      allow(DevelopmentTools).to receive(:clang_version).and_return(Version.new("21.0.0"))

      expect(described_class.detect_version).to eq("27.0")
    end

    it "loads Plist when version.plist exists" do
      contents = mktmpdir/"Contents"
      contents.mkpath
      (contents/"version.plist").write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>CFBundleShortVersionString</key>
            <string>26.3</string>
          </dict>
        </plist>
      XML
      allow(described_class).to receive_messages(installed?: true, prefix: contents/"Developer")
      allow(OS::Mac::CLT).to receive(:installed?).and_return(false)

      expect(described_class.detect_version).to eq("26.3")
    end
  end

  describe ".detect_version_from_clang_version" do
    it "preserves Xcode 26.3 for clang 17" do
      expect(described_class.detect_version_from_clang_version(Version.new("17.0.0"))).to eq("26.3")
    end
  end

  describe OS::Mac::CLT do
    describe ".latest_clang_version" do
      test_each(%w[27 26]) do |macos|
        it "recommends the Xcode 27 compiler on macOS #{macos}" do
          allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new(macos))
          allow(Hardware::CPU).to receive_messages(intel?: false, physical_cpu_arm64?: true)

          expect(described_class.latest_clang_version).to eq("2100.3.34.2")
        end
      end

      it "recommends the Xcode 26.6 compiler on Intel Tahoe" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("26"))
        allow(Hardware::CPU).to receive_messages(intel?: true, physical_cpu_arm64?: false)

        expect(described_class.latest_clang_version).to eq("2100.1.1.101")
      end
    end

    describe ".outdated?" do
      before do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("26"))
        allow(Hardware::CPU).to receive_messages(intel?: true, physical_cpu_arm64?: false)
      end

      it "accepts the latest Command Line Tools on Intel Tahoe" do
        allow(described_class).to receive(:detect_clang_version).and_return("2100.1.1.101")

        expect(described_class.outdated?).to be false
      end

      it "still reports older Command Line Tools on Intel Tahoe" do
        allow(described_class).to receive(:detect_clang_version).and_return("1700.6.4.2")

        expect(described_class.outdated?).to be true
      end

      it "reports Intel's latest Command Line Tools as outdated under Rosetta on Tahoe" do
        allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(true)
        allow(described_class).to receive(:detect_clang_version).and_return("2100.1.1.101")

        expect(described_class.outdated?).to be true
      end
    end

    describe ".update_instructions" do
      it "recommends Software Update on prerelease macOS" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new(HOMEBREW_MACOS_NEWEST_UNSUPPORTED))

        expect(described_class.update_instructions).to include("Update them from Software Update in System Settings.")
      end
    end
  end
end
