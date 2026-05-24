# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Quarantine do
  let(:klass) { Cask::Quarantine }

  describe ".cask!", :needs_macos do
    let(:cask) do
      instance_double(
        Cask::Cask,
        url:      "https://example.com/download",
        homepage: "https://example.com",
      )
    end

    it "sets the quarantine attribute on a file in a temporary directory" do
      mktmpdir do |tmpdir|
        download_path = tmpdir/"Test.dmg"
        download_path.write("test")

        expect(klass.status(download_path)).to eq("")

        klass.cask!(cask:, download_path:)

        expect(klass.status(download_path)).to match(
          /\A[0-9a-f]{4};[0-9a-f]+;Homebrew\\x20Cask;[0-9A-F-]{36}\z/i,
        )
      end
    end

    it "raises when the quarantine properties cannot be written" do
      mktmpdir do |tmpdir|
        download_path = tmpdir/"missing.dmg"

        expect do
          klass.cask!(cask:, download_path:)
        end.to raise_error(Cask::CaskQuarantineError, /Failed to set quarantine properties for URL/)
      end
    end
  end

  describe ".user_approved?" do
    let(:file) { Pathname("/tmp/Test.app") }

    before do
      allow(klass).to receive(:xattr).and_return(Pathname("/usr/bin/xattr"))
    end

    it "returns true when the user approval flag is set" do
      allow(klass).to receive(:status).with(file).and_return("01c3;6723b9fa;Safari;event-id")

      expect(klass.user_approved?(file)).to be(true)
    end

    it "returns false when the user approval flag is not set" do
      allow(klass).to receive(:status).with(file).and_return("0183;6723b9fa;Safari;event-id")

      expect(klass.user_approved?(file)).to be(false)
    end
  end

  describe ".signing_identity" do
    let(:file) { Pathname("/tmp/Test.app") }

    it "returns the signed identifier and Team ID" do
      result = instance_double(
        SystemCommand::Result,
        success?:      true,
        merged_output: <<~EOS,
          Identifier=sh.brew.test-app
          TeamIdentifier=ABCDE12345
          Authority=Developer ID Application: Brew Test (ABCDE12345)
        EOS
      )
      allow(klass).to receive(:system_command).with("codesign", args: ["-dvvv", file], print_stderr: false)
                                              .and_return(result)

      identity = klass.signing_identity(file)

      expect(identity).to have_attributes(identifier: "sh.brew.test-app", team_identifier: "ABCDE12345")
    end

    it "returns the signed identifier when the Team ID is missing" do
      result = instance_double(SystemCommand::Result, success?: true, merged_output: "Identifier=sh.brew.test-app\n")
      allow(klass).to receive(:system_command).with("codesign", args: ["-dvvv", file], print_stderr: false)
                                              .and_return(result)

      expect(klass.signing_identity(file)).to have_attributes(identifier:      "sh.brew.test-app",
                                                              team_identifier: nil)
    end

    it 'returns nil for the Team ID when it is "not set"' do
      result = instance_double(
        SystemCommand::Result,
        success?:      true,
        merged_output: "Identifier=com.apple.calculator\n" \
                       "TeamIdentifier=not set\n",
      )
      allow(klass).to receive(:system_command).with("codesign", args: ["-dvvv", file], print_stderr: false)
                                              .and_return(result)

      expect(klass.signing_identity(file)).to have_attributes(identifier:      "com.apple.calculator",
                                                              team_identifier: nil)
    end
  end
end
