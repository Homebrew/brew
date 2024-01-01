# typed: true
# frozen_string_literal: true

module Hardware
  class CPU
    class << self
      def optimization_flags
        @optimization_flags ||= begin
          flags = generic_optimization_flags.dup
          flags[:native] = arch_flag(Homebrew::EnvConfig.arch)
          flags
        end
      end

      def family
        return :arm if arm?
        return :ppc if ppc?
        return :dunno unless intel?

        # See https://software.intel.com/en-us/articles/intel-architecture-and-processor-identification-with-cpuid-model-and-family-numbers
        # and https://github.com/llvm-mirror/llvm/blob/HEAD/lib/Support/Host.cpp
        # and https://en.wikipedia.org/wiki/List_of_Intel_CPU_microarchitectures#Roadmap
        vendor_id = cpuinfo[/^vendor_id\s*: (.*)/, 1]
        cpu_family = cpuinfo[/^cpu family\s*: ([0-9]+)/, 1].to_i
        cpu_model = cpuinfo[/^model\s*: ([0-9]+)/, 1].to_i
        unknown = :"unknown_0x#{cpu_family.to_s(16)}_0x#{cpu_model.to_s(16)}"
        case vendor_id
        when "GenuineIntel"
          intel_family(cpu_family, cpu_model)
        when "AuthenticAMD"
          amd_family(cpu_family)
        end || unknown
      end

      def intel_family(family, cpu_model)
        case family
        when 0x06
          case cpu_model
          when 0x3a, 0x3e
            :ivybridge
          when 0x2a, 0x2d
            :sandybridge
          when 0x25, 0x2c, 0x2f
            :westmere
          when 0x1e, 0x1a, 0x2e
            :nehalem
          when 0x17, 0x1d
            :penryn
          when 0x0f, 0x16
            :merom
          when 0x0d
            :dothan
          when 0x1c, 0x26, 0x27, 0x35, 0x36
            :atom
          when 0x3c, 0x3f, 0x45, 0x46
            :haswell
          when 0x3d, 0x47, 0x4f, 0x56
            :broadwell
          when 0x4e, 0x55, 0x5e, 0x8e, 0x9e
            :skylake
          when 0x66
            :cannonlake
          when 0x6a, 0x6c, 0x7d, 0x7e
            :icelake
          end
        when 0x0f
          case cpu_model
          when 0x06
            :presler
          when 0x03, 0x04
            :prescott
          end
        end
      end

      def amd_family(family)
        case family
        when 0x06
          :amd_k7
        when 0x0f
          :amd_k8
        when 0x10
          :amd_k10
        when 0x11
          :amd_k8_k10_hybrid
        when 0x12
          :amd_k12
        when 0x14
          :bobcat
        when 0x15
          :bulldozer
        when 0x16
          :jaguar
        when 0x17
          :zen
        when 0x19
          :zen3
        end
      end

      # Supported CPU instructions
      def flags
        @flags ||= cpuinfo[/^(?:flags|Features)\s*: (.*)/, 1]&.split
        @flags ||= []
      end

      # Compatibility with Mac method, which returns lowercase symbols
      # instead of strings.
      def features
        @features ||= flags[1..].map(&:intern)
      end

      %w[aes altivec avx avx2 lm ssse3 sse4_2].each do |flag|
        define_method(:"#{flag}?") do
          T.bind(self, T.class_of(Hardware::CPU))
          flags.include? flag
        end
      end

      def sse3?
        flags.include?("pni") || flags.include?("sse3")
      end

      def sse4?
        flags.include? "sse4_1"
      end

      private

      def cpuinfo
        @cpuinfo ||= File.read("/proc/cpuinfo")
      end
    end
  end
end
