# frozen_string_literal: true

require "utils/bottles"

RSpec.describe Utils::Bottles::Tag do
  it "can parse macOS symbols with archs" do
    symbol = :arm64_big_sur
    tag = described_class.from_symbol(symbol)
    expect(tag.system).to eq(:big_sur)
    expect(tag.arch).to eq(:arm64)
    expect(tag.to_macos_version).to eq(MacOSVersion.from_symbol(:big_sur))
    expect(tag.macos?).to be true
    expect(tag.linux?).to be false
    expect(tag.to_sym).to eq(symbol)
  end

  it "can parse macOS symbols without archs" do
    symbol = :big_sur
    tag = described_class.from_symbol(symbol)
    expect(tag.system).to eq(:big_sur)
    expect(tag.arch).to eq(:x86_64)
    expect(tag.to_macos_version).to eq(MacOSVersion.from_symbol(:big_sur))
    expect(tag.macos?).to be true
    expect(tag.linux?).to be false
    expect(tag.to_sym).to eq(symbol)
  end

  it "can parse Linux symbols" do
    symbol = :x86_64_linux
    tag = described_class.from_symbol(symbol)
    expect(tag.system).to eq(:linux)
    expect(tag.arch).to eq(:x86_64)
    expect { tag.to_macos_version }.to raise_error(MacOSVersion::Error)
    expect(tag.macos?).to be false
    expect(tag.linux?).to be true
    expect(tag.to_sym).to eq(symbol)
  end

  describe "#==" do
    it "compares using the standardized arch" do
      monterey_intel = described_class.new(system: :monterey, arch: :intel)
      monterex_x86_64 = described_class.new(system: :monterey, arch: :x86_64)

      expect(monterey_intel).to eq monterex_x86_64
    end
  end

  describe "#standardized_arch" do
    it "returns :x86_64 for :intel" do
      expect(described_class.new(system: :all, arch: :intel).standardized_arch).to eq(:x86_64)
    end

    it "returns :arm64 for :arm" do
      expect(described_class.new(system: :all, arch: :arm).standardized_arch).to eq(:arm64)
    end
  end

  describe "#valid_combination?" do
    it "returns true for Intel" do
      tag = described_class.new(system: :big_sur, arch: :intel)
      expect(tag.valid_combination?).to be true
      tag = described_class.new(system: :linux, arch: :x86_64)
      expect(tag.valid_combination?).to be true
    end

    it "returns false for ARM on macOS Catalina or older" do
      tag = described_class.new(system: :catalina, arch: :arm64)
      expect(tag.valid_combination?).to be false
      tag = described_class.new(system: :mojave, arch: :arm)
      expect(tag.valid_combination?).to be false
    end

    it "returns true for ARM on macOS Big Sur or newer" do
      tag = described_class.new(system: :big_sur, arch: :arm64)
      expect(tag.valid_combination?).to be true
      tag = described_class.new(system: :monterey, arch: :arm)
      expect(tag.valid_combination?).to be true
      tag = described_class.new(system: :ventura, arch: :arm)
      expect(tag.valid_combination?).to be true
    end

    it "returns true for ARM on Linux" do
      tag = described_class.new(system: :linux, arch: :arm64)
      expect(tag.valid_combination?).to be true
      tag = described_class.new(system: :linux, arch: :arm)
      expect(tag.valid_combination?).to be true
    end
  end
end
