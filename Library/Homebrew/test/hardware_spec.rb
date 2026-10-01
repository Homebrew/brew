# typed: strict
# frozen_string_literal: true

require "hardware"

RSpec.describe Hardware do
  describe ".zig_cpu" do
    it "returns a specific Zig target CPU for known archs" do
      Hardware::CPU.optimization_flags.each_key do |arch|
        next if arch == :dunno

        expect(described_class.zig_cpu(arch)).not_to be :baseline
      end
    end

    it "returns baseline Zig target CPU for unknown arch" do
      expect(described_class.zig_cpu(:dunno)).to be :baseline
    end

    it "converts GCC -march with dashes to Zig-equivalent target CPU" do
      expect(described_class.zig_cpu(:"x86-64-v4")).to be :x86_64_v4
    end
  end
end
