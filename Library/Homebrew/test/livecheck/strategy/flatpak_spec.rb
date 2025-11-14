# frozen_string_literal: true

require "livecheck/strategy/flatpak"

RSpec.describe Homebrew::Livecheck::Strategy::Flatpak, :needs_linux, :needs_network do
  subject(:flatpak_strategy) { described_class }

  let(:flatpak_output) do
    <<~OUTPUT
              ID: org.gnome.Calculator
             Ref: app/org.gnome.Calculator/x86_64/stable
            Arch: x86_64
          Branch: stable
         Version: 49.1.1
         License: GPL-3.0-or-later
      Collection: org.flathub.Stable
        Download: 2.1 MB
       Installed: 5.4 MB
         Runtime: org.gnome.Platform/x86_64/49
             Sdk: org.gnome.Sdk/x86_64/49
    OUTPUT
  end

  let(:cask) do
    Cask::Cask.new("test-flatpak") do
      version "1.0.0"
      sha256 :no_check
      flatpak "org.gnome.Calculator"
    end
  end

  let(:cask_with_remote) do
    Cask::Cask.new("test-flatpak-remote") do
      version "1.0.0"
      sha256 :no_check
      flatpak "com.example.App", remote: "custom"
    end
  end

  describe "::match?" do
    it "returns false for any URL" do
      expect(flatpak_strategy.match?("https://example.com")).to be false
    end
  end

  describe "::find_versions" do
    let(:options) { Homebrew::Livecheck::Options.new }

    before do
      allow(flatpak_strategy).to receive(:which).with("flatpak").and_return(Pathname.new("/usr/bin/flatpak"))
    end

    context "when cask has no flatpak artifact" do
      let(:cask_without_flatpak) do
        Cask::Cask.new("no-flatpak") do
          version "1.0.0"
          sha256 :no_check
          url "https://example.com/app.dmg"
          app "App.app"
        end
      end

      it "returns error message" do
        match_data = flatpak_strategy.find_versions(cask: cask_without_flatpak, url: nil, options:)

        expect(match_data[:matches]).to be_empty
        expect(match_data[:messages]).to eq(["Cask does not have a flatpak stanza"])
      end
    end

    context "when flatpak command is not found" do
      before do
        allow(flatpak_strategy).to receive(:which).with("flatpak").and_return(nil)
      end

      it "returns error message" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, options:)

        expect(match_data[:matches]).to be_empty
        expect(match_data[:messages]).to eq(["flatpak command not found"])
      end
    end

    context "when flatpak remote-info succeeds" do
      before do
        allow(flatpak_strategy).to receive(:system_command).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [flatpak_output, "", instance_double(Process::Status, success?: true)],
          ),
        )
      end

      it "extracts version from output" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, options:)

        expect(match_data[:matches]).to eq({ "49.1.1" => Version.new("49.1.1") })
        expect(match_data[:messages]).to be_nil
      end

      it "uses the correct remote" do
        expect(flatpak_strategy).to receive(:system_command).with(
          "flatpak",
          hash_including(args: ["remote-info", "--system", "flathub", "org.gnome.Calculator"]),
        ).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [flatpak_output, "", instance_double(Process::Status, success?: true)],
          ),
        )

        flatpak_strategy.find_versions(cask:, url: nil, options:)
      end

      it "uses custom remote when specified" do
        expect(flatpak_strategy).to receive(:system_command).with(
          "flatpak",
          hash_including(args: ["remote-info", "--system", "custom", "com.example.App"]),
        ).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [flatpak_output, "", instance_double(Process::Status, success?: true)],
          ),
        )

        flatpak_strategy.find_versions(cask: cask_with_remote, url: nil, options:)
      end
    end

    context "when flatpak remote-info fails" do
      before do
        allow(flatpak_strategy).to receive(:system_command).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: ["", "error: Remote not found", instance_double(Process::Status, success?: false)],
          ),
        )
      end

      it "returns error message from stderr" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, options:)

        expect(match_data[:matches]).to be_empty
        expect(match_data[:messages]).to eq(["error: Remote not found"])
      end
    end

    context "when version line is missing" do
      before do
        output_without_version = flatpak_output.gsub(/^\s*Version:.*$/, "")
        allow(flatpak_strategy).to receive(:system_command).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [output_without_version, "", instance_double(Process::Status, success?: true)],
          ),
        )
      end

      it "returns error message" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, options:)

        expect(match_data[:matches]).to be_empty
        expect(match_data[:messages]).to eq(["No version information found in flatpak remote-info output"])
      end
    end

    context "with regex" do
      let(:regex) { /^(\d+\.\d+)/ }

      before do
        allow(flatpak_strategy).to receive(:system_command).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [flatpak_output, "", instance_double(Process::Status, success?: true)],
          ),
        )
      end

      it "applies regex to version" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, regex:, options:)

        expect(match_data[:matches]).to eq({ "49.1" => Version.new("49.1") })
      end
    end

    context "with block" do
      before do
        allow(flatpak_strategy).to receive(:system_command).and_return(
          instance_double(
            SystemCommand::Result,
            to_a: [flatpak_output, "", instance_double(Process::Status, success?: true)],
          ),
        )
      end

      it "passes version to block" do
        match_data = flatpak_strategy.find_versions(cask:, url: nil, options:) do |version|
          version.split(".").first
        end

        expect(match_data[:matches]).to eq({ "49" => Version.new("49") })
      end
    end
  end
end
