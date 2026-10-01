# typed: strict
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

  describe ".from_arg" do
    it "parses an explicit tag argument" do
      expect(described_class.from_arg(:arm64_big_sur, os: :monterey, arch: :x86_64))
        .to eq(described_class.new(system: :big_sur, arch: :arm64))
    end

    it "builds from the given os and arch when no argument is passed" do
      expect(described_class.from_arg(nil, os: :monterey, arch: :arm64))
        .to eq(described_class.new(system: :monterey, arch: :arm64))
    end
  end

  describe "#==" do
    it "compares using the standardized arch" do
      monterey_intel = described_class.new(system: :monterey, arch: :intel)
      monterex_x86_64 = described_class.new(system: :monterey, arch: :x86_64)

      expect(monterey_intel).to eq monterex_x86_64
    end
  end

  describe "#standardized_arch" do
    specify do
      expect(described_class.new(system: :all, arch: :intel).standardized_arch).to eq(:x86_64)
      expect(described_class.new(system: :all, arch: :arm).standardized_arch).to eq(:arm64)
    end
  end

  describe "#padded_prefix" do
    it "returns distinct 64-byte prefixes for supported bottle platforms" do
      prefixes = [:arm64_tahoe, :arm64_linux, :x86_64_linux].map do |tag|
        described_class.from_symbol(tag).padded_prefix
      end

      expect([prefixes.uniq.length, *prefixes.map { |prefix| prefix&.bytesize }]).to eq([3, 64, 64, 64])
    end

    it "returns nil for Intel macOS" do
      expect(described_class.from_symbol(:tahoe).padded_prefix).to be_nil
    end
  end
end
