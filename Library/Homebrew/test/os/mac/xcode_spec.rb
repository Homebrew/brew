# typed: strict
# frozen_string_literal: true

require "os/mac/xcode"

RSpec.describe OS::Mac::Xcode, :needs_macos do
  describe ".latest_version" do
    test_each_hash({ "27" => "27.0", "26" => "27.0", "15" => "26.3", "14" => "16.2",
                    "13" => "15.2", "12" => "14.2", "11" => "13.2.1" }) do |macos, xcode|
      it "recommends Xcode #{xcode} on macOS #{macos}" do
        allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(true)

        expect(described_class.latest_version(macos: MacOSVersion.new(macos))).to eq(xcode)
      end
    end

    it "caps Xcode at 26.6 on Intel Tahoe" do
      allow(Hardware::CPU).to receive_messages(intel?: true, physical_cpu_arm64?: false)

      expect(described_class.latest_version(macos: MacOSVersion.new("26"))).to eq("26.6")
    end

    it "recommends Xcode 27 under Rosetta on Tahoe" do
      allow(Hardware::CPU).to receive_messages(intel?: true, physical_cpu_arm64?: true)

      expect(described_class.latest_version(macos: MacOSVersion.new("26"))).to eq("27.0")
    end

    it "caps Xcode for an Intel Tahoe target on Apple silicon" do
      allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(true)

      expect(described_class.latest_version(macos: MacOSVersion.new("26"), arm64: false)).to eq("26.6")
    end

    it "recommends Xcode 27 for an Apple silicon Tahoe target on Intel" do
      allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(false)

      expect(described_class.latest_version(macos: MacOSVersion.new("26"), arm64: true)).to eq("27.0")
    end
  end

  describe ".detect_version" do
    it "does not infer a version from the Command Line Tools" do
      allow(described_class).to receive_messages(installed?: false, prefix: nil)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(true)

      expect(described_class.detect_version).to be_nil
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

  describe OS::Mac::CLT do
    describe ".latest_version" do
      test_each_hash({ "27" => "27.0", "26" => "27.0", "15" => "26.3", "14" => "16.2",
                      "13" => "15.1", "12" => "14.2", "11" => "13.2" }) do |macos, clt|
        it "recommends Command Line Tools #{clt} on macOS #{macos}" do
          allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new(macos))
          allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(true)

          expect(described_class.latest_version).to eq(clt)
        end
      end

      it "follows Xcode updates on Intel Tahoe" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("26"))
        allow(Hardware::CPU).to receive(:physical_cpu_arm64?).and_return(false)
        allow(OS::Mac::Xcode).to receive(:latest_version).and_return("26.7")

        expect(described_class.latest_version).to eq("26.7")
      end
    end

    describe ".reinstall_instructions" do
      it "recommends a released Command Line Tools version on Ventura" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("13"))

        expect(described_class.reinstall_instructions).to include("Command Line Tools for Xcode 15.1.\n")
      end
    end

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

      it "returns the compiler version for a simulated macOS and architecture" do
        expect(described_class.latest_clang_version(macos: MacOSVersion.new("12"), arm64: false))
          .to eq("1400.0.29.202")
      end
    end

    describe ".outdated?" do
      before do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new("26"))
        allow(Hardware::CPU).to receive_messages(intel?: true, physical_cpu_arm64?: false)
        allow(described_class).to receive(:version).and_return(Version::NULL)
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

      it "does not report unavailable compiler metadata as outdated" do
        allow(described_class).to receive(:detect_clang_version).and_return(nil)

        expect(described_class.outdated?).to be false
      end

      context "when the package version is known" do
        before do
          allow(described_class).to receive_messages(
            latest_version:       "27.0",
            latest_clang_version: "2100.3.34.2",
            detect_clang_version: "2100.3.34.1",
          )
        end

        test_each(%w[27.2.0.0.1792148227 27.0.1.0.1792148227]) do |version|
          it "accepts CLT #{version} despite its lower compiler build" do
            allow(described_class).to receive(:version).and_return(Version.new(version))

            expect(described_class.outdated?).to be false
          end
        end

        it "checks the compiler when only the receipt timestamp is newer" do
          allow(described_class).to receive(:version).and_return(Version.new("27.0.0.0.1792148227"))

          expect(described_class.outdated?).to be true
        end

        it "still reports an older release with an older compiler" do
          allow(described_class).to receive_messages(
            version:              Version.new("26.6.0.0.1792148227"),
            detect_clang_version: "2100.1.1.101",
          )

          expect(described_class.outdated?).to be true
        end

        it "accepts the recommended release with the current compiler" do
          allow(described_class).to receive_messages(
            version:              Version.new("27.0.0.0.1792148227"),
            detect_clang_version: "2100.3.34.2",
          )

          expect(described_class.outdated?).to be false
        end
      end
    end

    describe ".installed?" do
      it "detects Command Line Tools without a package receipt" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("#{OS::Mac::CLT::PKG_PATH}/usr/bin/clang").and_return(true)
        allow(MacOS).to receive(:pkgutil_info).and_return("")

        expect(described_class.installed?).to be true
      end
    end

    describe ".detect_version" do
      it "leaves the version unknown without a package receipt" do
        allow(described_class).to receive(:installed?).and_return(true)
        allow(MacOS).to receive(:pkgutil_info).and_return("")

        expect(described_class.detect_version).to be_nil
      end
    end

    describe ".below_minimum_version?" do
      it "does not treat an unknown version as below the minimum" do
        allow(described_class).to receive_messages(installed?: true, version: Version::NULL)

        expect(described_class.below_minimum_version?).to be false
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
