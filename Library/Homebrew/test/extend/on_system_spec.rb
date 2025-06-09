# frozen_string_literal: true

require "extend/on_system"

RSpec.describe OnSystem do
  shared_examples "a class with on_arch methods" do
    it "adds on_arch methods to class for `ARCH_OPTIONS`" do
      OnSystem::ARCH_OPTIONS.each do |arch|
        expect(subject.method_defined?(:"on_#{arch}")).to be true
      end
    end
  end

  shared_examples "a class with on_base_os methods" do
    it "adds on_os methods to class for `BASE_OS_OPTIONS`" do
      OnSystem::BASE_OS_OPTIONS.each do |os|
        expect(subject.method_defined?(:"on_#{os}")).to be true
      end
    end
  end

  shared_examples "a class with on_macos methods" do
    it "adds on_os methods to class for `MacOSVersion::SYMBOLS` keys" do
      MacOSVersion::SYMBOLS.each_key do |os|
        expect(subject.method_defined?(:"on_#{os}")).to be true
      end
    end
  end

  describe "UsesOnSystem" do
    uses_on_system_empty = described_class::UsesOnSystem.new
    uses_on_system_present = described_class::UsesOnSystem.new(arm: true)

    describe "#empty?" do
      it "returns true if all properties are default values" do
        expect(uses_on_system_empty.empty?).to be true
      end

      it "returns false if any properties have a non-default value" do
        expect(uses_on_system_present.empty?).to be false
      end
    end

    describe "#present?" do
      it "returns true if object is not empty" do
        expect(uses_on_system_present.present?).to be true
      end

      it "returns false if object is empty" do
        expect(uses_on_system_empty.present?).to be false
      end
    end
  end

  describe "::comparator_from_or_condition" do
    it 'returns ">=" for `:or_newer` symbol' do
      expect(described_class.comparator_from_or_condition(:or_newer)).to eq(">=")
    end

    it 'returns "<=" for `:or_older` symbol' do
      expect(described_class.comparator_from_or_condition(:or_older)).to eq("<=")
    end

    it 'returns "==" for an unsupported symbol' do
      expect(described_class.comparator_from_or_condition(:nonexistent)).to eq("==")
    end

    it 'returns "==" for `nil`' do
      expect(described_class.comparator_from_or_condition(nil)).to eq("==")
    end
  end

  describe "::arch_condition_met?" do
    it "returns true if current arch equals provided arch" do
      Homebrew::SimulateSystem.with(arch: :arm) do
        expect(described_class.arch_condition_met?(:arm)).to be true
      end
    end

    it "returns false if current arch does not equal provided arch" do
      Homebrew::SimulateSystem.with(arch: :arm) do
        expect(described_class.arch_condition_met?(:intel)).to be false
      end
    end

    it "raises error if provided arch is not valid" do
      expect { described_class.arch_condition_met?(:nonexistent_arch) }
        .to raise_error(ArgumentError)
    end
  end

  describe "::os_condition_met?" do
    let(:newest_macos) { MacOSVersion::SYMBOLS.keys.first }

    it "returns result of `SimulateSystem.simulating_or_running_on_<os_name>` for supported OS" do
      Homebrew::SimulateSystem.with(os: newest_macos) do
        # This needs to use a value from `BASE_OS_OPTIONS`
        expect(described_class.os_condition_met?(:macos)).to be true
      end
    end

    it "returns false if `os_name` is a macOS version but OS is Linux" do
      Homebrew::SimulateSystem.with(os: :linux) do
        expect(described_class.os_condition_met?(newest_macos)).to be false
      end
    end

    it "returns false if `os_name` is a macOS version but current OS is `:generic`" do
      allow(Homebrew::SimulateSystem).to receive(:current_os).and_return(:generic)
      expect(described_class.os_condition_met?(newest_macos)).to be false
    end

    it "returns false if current OS is `:macos` and `os_name` is a macOS version" do
      # A generic macOS version is treated as less than any other version.
      Homebrew::SimulateSystem.with(os: :macos) do
        expect(described_class.os_condition_met?(newest_macos)).to be false
      end
    end

    it "returns true if current OS equals the `os_name` macOS version" do
      Homebrew::SimulateSystem.with(os: newest_macos) do
        expect(described_class.os_condition_met?(newest_macos)).to be true
      end
    end

    it "returns true if current OS meets the `or_condition` for `os_name` macOS version" do
      current_os = :ventura
      Homebrew::SimulateSystem.with(os: current_os) do
        expect(described_class.os_condition_met?(current_os, :or_newer)).to be true
        expect(described_class.os_condition_met?(:big_sur, :or_newer)).to be true
        expect(described_class.os_condition_met?(current_os, :or_older)).to be true
        expect(described_class.os_condition_met?(newest_macos, :or_older)).to be true
      end
    end

    it "returns false if current OS does not meet the `or_condition` for `os_name` macOS version" do
      Homebrew::SimulateSystem.with(os: :ventura) do
        expect(described_class.os_condition_met?(newest_macos, :or_newer)).to be false
        expect(described_class.os_condition_met?(:big_sur, :or_older)).to be false
      end
    end

    it "raises an error if `os_name` is not valid" do
      expect { described_class.os_condition_met?(:nonexistent_os) }
        .to raise_error(ArgumentError, /Invalid OS condition:/)
    end

    it "raises an error if `os_name` is a macOS version but `or_condition` is not valid" do
      expect do
        described_class.os_condition_met?(newest_macos, :nonexistent_condition)
      end.to raise_error(ArgumentError, /Invalid OS `or_\*` condition:/)
    end
  end

  describe "::condition_from_method_name" do
    it "returns a symbol with any `on_` prefix removed" do
      expect(described_class.condition_from_method_name(:on_arm)).to eq(:arm)
    end

    it "returns provided symbol if there is no `on_` prefix" do
      expect(described_class.condition_from_method_name(:arm)).to eq(:arm)
    end
  end

  describe "::setup_arch_methods" do
    subject do
      klass = Class.new
      described_class.setup_arch_methods(klass)
      klass
    end

    it_behaves_like "a class with on_arch methods"
  end

  describe "::setup_base_os_methods" do
    subject do
      klass = Class.new
      described_class.setup_base_os_methods(klass)
      klass
    end

    it_behaves_like "a class with on_base_os methods"
  end

  describe "::setup_macos_methods" do
    subject do
      klass = Class.new
      described_class.setup_macos_methods(klass)
      klass
    end

    it_behaves_like "a class with on_macos methods"
  end

  describe "::included" do
    it "raises an error" do
      expect { Class.new { include OnSystem } }
        .to raise_error(/Do not include `OnSystem` directly/)
    end
  end

  describe "::MacOSAndLinux" do
    subject { Class.new { include OnSystem::MacOSAndLinux } }

    it "can be included" do
      expect { Class.new { include OnSystem::MacOSAndLinux } }.not_to raise_error
    end

    it_behaves_like "a class with on_arch methods"
    it_behaves_like "a class with on_base_os methods"
    it_behaves_like "a class with on_macos methods"
  end

  describe "::MacOSOnly" do
    subject { Class.new { include OnSystem::MacOSAndLinux } }

    it "can be included" do
      expect { Class.new { include OnSystem::MacOSOnly } }.not_to raise_error
    end

    it_behaves_like "a class with on_arch methods"
    it_behaves_like "a class with on_macos methods"
  end
end
