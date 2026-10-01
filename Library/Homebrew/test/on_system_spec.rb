# typed: strict
# frozen_string_literal: true

require "on_system"

RSpec.describe OnSystem do
  describe "::os_condition_met?" do
    it "returns true for `:macos` when simulating macOS" do
      Homebrew::SimulateSystem.with(os: :macos) do
        expect(described_class.os_condition_met?(:macos)).to be true
      end
    end

    it "returns false for `:linux` when simulating macOS" do
      Homebrew::SimulateSystem.with(os: :macos) do
        expect(described_class.os_condition_met?(:linux)).to be false
      end
    end

    it "raises an error for an unknown `os_name`" do
      expect { described_class.os_condition_met?(:unknown_os_name) }
        .to raise_error(ArgumentError, /Invalid OS condition/)
    end

    it "raises an error for an unknown `or_condition`" do
      expect { described_class.os_condition_met?(:tahoe, :unknown_or_condition) }
        .to raise_error(ArgumentError, /Invalid OS `or_\*` condition/)
    end

    it "returns false for a macOS version when simulating Linux" do
      Homebrew::SimulateSystem.with(os: :linux) do
        expect(described_class.os_condition_met?(:tahoe, :or_newer)).to be false
      end
    end

    it "returns false for a macOS version when not simulating or running on macOS" do
      allow(Homebrew::SimulateSystem).to receive(:simulating_or_running_on_macos?).and_return(false)

      expect(described_class.os_condition_met?(:tahoe, :or_newer)).to be false
    end

    it "assumes the oldest macOS version when simulating a generic macOS version" do
      Homebrew::SimulateSystem.with(os: :macos) do
        expect(described_class.os_condition_met?(:tahoe, :or_older)).to be true
      end
    end

    it "returns true for an `:or_newer` condition on a newer macOS version" do
      Homebrew::SimulateSystem.with(os: :golden_gate) do
        expect(described_class.os_condition_met?(:tahoe, :or_newer)).to be true
      end
    end

    it "returns false for an `:or_newer` condition on an older macOS version" do
      Homebrew::SimulateSystem.with(os: :sequoia) do
        expect(described_class.os_condition_met?(:tahoe, :or_newer)).to be false
      end
    end

    it "returns true for an `:or_older` condition on an older macOS version" do
      Homebrew::SimulateSystem.with(os: :sequoia) do
        expect(described_class.os_condition_met?(:tahoe, :or_older)).to be true
      end
    end

    it "returns false for an `:or_older` condition on a newer macOS version" do
      Homebrew::SimulateSystem.with(os: :golden_gate) do
        expect(described_class.os_condition_met?(:tahoe, :or_older)).to be false
      end
    end

    it "returns true for a macOS version condition on the same macOS version" do
      Homebrew::SimulateSystem.with(os: :tahoe) do
        expect(described_class.os_condition_met?(:tahoe)).to be true
      end
    end

    it "returns false for a macOS version condition on another macOS version" do
      Homebrew::SimulateSystem.with(os: :golden_gate) do
        expect(described_class.os_condition_met?(:tahoe)).to be false
      end
    end
  end
end
