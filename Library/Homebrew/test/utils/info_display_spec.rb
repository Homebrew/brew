# typed: true
# frozen_string_literal: true

require "utils/info_display"

RSpec.describe Utils::InfoDisplay do
  describe ".requirement_for_other_os?" do
    test_each([
      [:macos, MacOSRequirement, false],
      [:macos, LinuxRequirement, true],
      [:linux, MacOSRequirement, true],
      [:linux, LinuxRequirement, false],
    ]) do |(os, requirement_class, expected)|
      it "identifies #{requirement_class} on #{os}" do
        Homebrew::SimulateSystem.with(os:) do
          expect(described_class.requirement_for_other_os?(requirement_class.new)).to eq(expected)
        end
      end
    end

    it "treats macOS and Linux requirements as other OS requirements on generic OS" do
      allow(Homebrew::SimulateSystem).to receive_messages(simulating_or_running_on_macos?: false,
                                                          simulating_or_running_on_linux?: false)

      expect([MacOSRequirement.new, LinuxRequirement.new].map do |requirement|
        described_class.requirement_for_other_os?(requirement)
      end).to eq([true, true])
    end
  end

  describe ".package_summary" do
    let(:cask) { Cask::Cask.new("example") { version "2.0" } }

    it "formats the supplied title" do
      expect(described_class.package_summary(
               formula_or_cask: cask,
               title: Utils::InfoDisplay::Title.new(
                 name: "example", display_names: ["Example"], version: "2.0",
                 installed_version: "1.0", installed: true, outdated: true, auto_updates: true
               ),
               installation_status: ["Installed"], source_url: nil,
               installed_versions: [], verbose: false
             )).to eq("==> example (Example): 1.0 → 2.0 (auto_updates)\nInstalled")
    end

    it "places cask metadata after the source" do
      allow(described_class).to receive(:metadata_lines).with(cask).and_return(["Pinned: 1.0"])

      expect(described_class.package_summary(
               formula_or_cask: cask, title: Utils::InfoDisplay::Title.new(name: "example", version: "2.0"),
               installation_status: ["Installed"],
               source_url: "https://example.com/cask.rb", installed_versions: [], verbose: false
             )).to eq("==> example: 2.0\nInstalled\nFrom: https://example.com/cask.rb\nPinned: 1.0")
    end
  end

  describe ".package_title" do
    it "formats formula version, status and attributes" do
      title = Utils::InfoDisplay::Title.new(
        name: "example", version: "2.0", installed_version: "1.0", installed: true,
        outdated: true, stable: true, bottled: true, head: true, keg_only: true
      )

      expect(described_class.package_title(title)).to eq("==> example: 1.0 → stable 2.0 (bottled), HEAD [keg-only]")
    end

    it "formats cask names and automatic updates" do
      title = Utils::InfoDisplay::Title.new(
        name: "example", display_names: ["Example", "Another"], version: "2.0",
        installed_version: "1.0", installed: true, outdated: true, auto_updates: true
      )

      expect(described_class.package_title(title)).to eq("==> example (Example, Another): 1.0 → 2.0 (auto_updates)")
    end

    it "formats a HEAD-only outdated formula" do
      title = Utils::InfoDisplay::Title.new(
        name: "example", installed_version: "1.0", installed: true, outdated: true, head: true,
      )

      expect(described_class.package_title(title)).to eq("==> example: 1.0 → HEAD")
    end
  end

  describe ".requirements_section" do
    it "omits an empty section" do
      expect(described_class.requirements_section([])).to be_nil
    end

    it "groups requirements in order and optionally removes the Linux alternative" do
      allow($stdout).to receive(:tty?).and_return(false)
      required = MacOSRequirement.new
      build = ArchRequirement.new([:arm64])
      optional = ArchRequirement.new([:x86_64])
      allow(required).to receive_messages(display_s: "macOS (or Linux)", satisfied?: true)
      allow(build).to receive_messages(display_s: "build architecture", build?: true, required?: false,
                                       satisfied?: true)
      allow(optional).to receive_messages(display_s: "optional architecture", optional?: true, required?: false,
                                          satisfied?: false)

      expect(described_class.requirements_section([optional, required, build], omit_macos_linux: true))
        .to eq("==> Requirements\nBuild: build architecture\nRequired: macOS\nOptional: optional architecture")
    end

    it "retains the Linux alternative by default" do
      allow($stdout).to receive(:tty?).and_return(false)
      requirement = MacOSRequirement.new
      allow(requirement).to receive_messages(display_s: "macOS (or Linux)", satisfied?: true)

      expect(described_class.requirements_section([requirement]))
        .to eq("==> Requirements\nRequired: macOS (or Linux)")
    end
  end
end
