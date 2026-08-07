# typed: strict
# frozen_string_literal: true

require "os/mac/xcode"

RSpec.describe OS::Mac::Xcode, :needs_macos do
  describe ".detect_version" do
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
    describe ".update_instructions" do
      it "recommends Software Update on prerelease macOS" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new(HOMEBREW_MACOS_NEWEST_UNSUPPORTED))

        expect(described_class.update_instructions).to include("Update them from Software Update in System Settings.")
      end
    end
  end
end
