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

    it "returns false on macOS when simulating Linux", :needs_macos do
      described_class.clear
      described_class.os = :linux
      expect(described_class.simulating_or_running_on_macos?).to be false
    end

    it "returns true on Linux when simulating a generic macOS version", :needs_linux do
      described_class.clear
      described_class.os = :macos
      expect(described_class.simulating_or_running_on_macos?).to be true
    end

    it "returns true on Linux when simulating a specific macOS version", :needs_linux do
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

    it "returns true on macOS when simulating Linux", :needs_macos do
      described_class.clear
      described_class.os = :linux
      expect(described_class.simulating_or_running_on_linux?).to be true
    end

    it "returns false on Linux when simulating a generic macOS version", :needs_linux do
      described_class.clear
      described_class.os = :macos
      expect(described_class.simulating_or_running_on_linux?).to be false
    end

    it "returns false on Linux when simulating a specific macOS version", :needs_linux do
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

    it "returns `:linux` when simulating Linux on macOS", :needs_macos do
      described_class.clear
      described_class.os = :linux
      expect(described_class.current_os).to eq :linux
    end

    it "returns `:macos` when simulating a generic macOS version on Linux", :needs_linux do
      described_class.clear
      described_class.os = :macos
      expect(described_class.current_os).to eq :macos
    end

    it "returns `:macos` when simulating a specific macOS version on Linux", :needs_linux do
      described_class.clear
      described_class.os = :monterey
      expect(described_class.current_os).to eq :monterey
    end

    it "returns the current macOS version on macOS with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_macos do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.current_os).to eq MacOS.version.to_sym
    end

    it "returns `:macos` on Linux with HOMEBREW_SIMULATE_MACOS_ON_LINUX", :needs_linux do
      described_class.clear
      ENV["HOMEBREW_SIMULATE_MACOS_ON_LINUX"] = "1"
      expect(described_class.current_os).to eq :macos
    end
  end
end
