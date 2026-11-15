# typed: strict
# frozen_string_literal: true

require "settings"

RSpec.describe Homebrew::SimulateSystem do
  after do
    described_class.clear
  end

  describe "::simulating_or_running_on_macos?" do
    it "returns true on macOS", :needs_macos do
      described_class.clear
      expect(described_class.simulating_or_running_on_macos?).to be true
    end

    it "returns false on Linux", :needs_linux do
      described_class.clear
      expect(described_class.simulating_or_running_on_macos?).to be false
    end

    it "returns false when simulating Linux" do
      described_class.clear
      described_class.os = :linux
      expect(described_class.simulating_or_running_on_macos?).to be false
    end

    it "returns true when simulating a generic macOS version" do
      described_class.clear
      described_class.os = :macos
      expect(described_class.simulating_or_running_on_macos?).to be true
    end

    it "returns true when simulating a specific macOS version" do
      described_class.clear
      described_class.os = :monterey
      expect(described_class.simulating_or_running_on_macos?).to be true
    end

    it "returns true on Linux with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_linux do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.simulating_or_running_on_macos?).to be true
    end
  end

  describe "::simulating_or_running_on_linux?" do
    it "returns true on Linux", :needs_linux do
      described_class.clear
      expect(described_class.simulating_or_running_on_linux?).to be true
    end

    it "returns false on macOS", :needs_macos do
      described_class.clear
      expect(described_class.simulating_or_running_on_linux?).to be false
    end

    it "returns true when simulating Linux" do
      described_class.clear
      described_class.os = :linux
      expect(described_class.simulating_or_running_on_linux?).to be true
    end

    it "returns false when simulating a generic macOS version" do
      described_class.clear
      described_class.os = :macos
      expect(described_class.simulating_or_running_on_linux?).to be false
    end

    it "returns false when simulating a specific macOS version" do
      described_class.clear
      described_class.os = :monterey
      expect(described_class.simulating_or_running_on_linux?).to be false
    end

    it "returns false on Linux with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_linux do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.simulating_or_running_on_linux?).to be false
    end
  end

  describe "::simulating?" do
    it "returns false without any simulation" do
      described_class.clear
      expect(described_class.simulating?).to be false
    end

    it "returns true when simulating an OS" do
      described_class.clear
      described_class.os = :linux
      expect(described_class.simulating?).to be true
    end

    it "returns true when simulating an architecture" do
      described_class.clear
      described_class.arch = :arm
      expect(described_class.simulating?).to be true
    end
  end

  describe "::current_arch" do
    it "returns the current architecture" do
      described_class.clear
      expect(described_class.current_arch).to eq Hardware::CPU.type
    end

    it "returns the simulated architecture" do
      described_class.clear
      simulated_arch = if Hardware::CPU.arm?
        :intel
      else
        :arm
      end
      described_class.arch = simulated_arch
      expect(described_class.current_arch).to eq simulated_arch
    end
  end

  describe "::current_os" do
    it "returns the current macOS version on macOS", :needs_macos do
      described_class.clear
      expect(described_class.current_os).to eq MacOS.version.to_sym
    end

    it "returns `:linux` on Linux", :needs_linux do
      described_class.clear
      expect(described_class.current_os).to eq :linux
    end

    it "returns `:linux` when simulating Linux" do
      described_class.clear
      described_class.os = :linux
      expect(described_class.current_os).to eq :linux
    end

    it "returns `:macos` when simulating a generic macOS version" do
      described_class.clear
      described_class.os = :macos
      expect(described_class.current_os).to eq :macos
    end

    it "returns `:monterey` when simulating a specific macOS version" do
      described_class.clear
      described_class.os = :monterey
      expect(described_class.current_os).to eq :monterey
    end

    it "returns the current macOS version on macOS with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_macos do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.current_os).to eq MacOS.version.to_sym
    end

    it "returns the newest supported macOS symbol on Linux with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_linux do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.current_os).to eq MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
    end
  end
end
