# typed: true
# frozen_string_literal: true

require "utils/popen"

# Helper module for querying hardware information.
module Hardware
  # Helper module for querying CPU information.
  class CPU
    INTEL_32BIT_ARCHS = [:i386].freeze
    INTEL_64BIT_ARCHS = [:x86_64].freeze
    INTEL_ARCHS       = (INTEL_32BIT_ARCHS + INTEL_64BIT_ARCHS).freeze
    PPC_32BIT_ARCHS   = [:ppc, :ppc32, :ppc7400, :ppc7450, :ppc970].freeze
    PPC_64BIT_ARCHS   = [:ppc64, :ppc64le, :ppc970].freeze
    PPC_ARCHS         = (PPC_32BIT_ARCHS + PPC_64BIT_ARCHS).freeze
    ARM_64BIT_ARCHS   = [:arm64, :aarch64].freeze
    ARM_ARCHS         = ARM_64BIT_ARCHS
    ALL_ARCHS = [
      *INTEL_ARCHS,
      *PPC_ARCHS,
      *ARM_ARCHS,
    ].freeze

    INTEL_64BIT_OLDEST_CPU = :core2

    class << self
      def optimization_flags
        @optimization_flags ||= {
          native:             arch_flag("native"),
          ivybridge:          "-march=ivybridge",
          sandybridge:        "-march=sandybridge",
          westmere:           "-march=westmere",
          nehalem:            "-march=nehalem",
          core2:              "-march=core2",
          core:               "-march=prescott",
          arm_vortex_tempest: "", # TODO: -mcpu=apple-m1 when we've patched all our GCCs to support it
          armv6:              "-march=armv6",
          armv8:              "-march=armv8-a",
          ppc64:              "-mcpu=powerpc64",
          ppc64le:            "-mcpu=powerpc64le",
        }.freeze
      end
      alias generic_optimization_flags optimization_flags

      sig { returns(Symbol) }
      def arch_32_bit
        if arm?
          :arm
        elsif intel?
          :i386
        elsif ppc32?
          :ppc32
        else
          :dunno
        end
      end

      sig { returns(Symbol) }
      def arch_64_bit
        if arm?
          :arm64
        elsif intel?
          :x86_64
        elsif ppc64le?
          :ppc64le
        elsif ppc64?
          :ppc64
        else
          :dunno
        end
      end

      def arch
        case bits
        when 32
          arch_32_bit
        when 64
          arch_64_bit
        else
          :dunno
        end
      end

      sig { returns(Symbol) }
      def type
        case RUBY_PLATFORM
        when /x86_64/, /i\d86/ then :intel
        when /arm/, /aarch64/ then :arm
        when /ppc|powerpc/ then :ppc
        else :dunno
        end
      end

      sig { returns(Symbol) }
      def family
        :dunno
      end

      def cores
        return @cores if @cores

        @cores = Utils.popen_read("getconf", "_NPROCESSORS_ONLN").chomp.to_i
        @cores = 1 unless $CHILD_STATUS.success?
        @cores
      end

      def bits
        @bits ||= case RUBY_PLATFORM
        when /x86_64/, /ppc64|powerpc64/, /aarch64|arm64/ then 64
        when /i\d86/, /ppc/, /arm/ then 32
        end
      end

      sig { returns(T::Boolean) }
      def sse4?
        RUBY_PLATFORM.to_s.include?("x86_64")
      end

      def is_32_bit?
        bits == 32
      end

      def is_64_bit?
        bits == 64
      end

      def intel?
        type == :intel
      end

      def ppc?
        type == :ppc
      end

      def ppc32?
        ppc? && is_32_bit?
      end

      def ppc64le?
        ppc? && is_64_bit? && little_endian?
      end

      def ppc64?
        ppc? && is_64_bit? && big_endian?
      end

      def arm?
        type == :arm
      end

      def little_endian?
        !big_endian?
      end

      def big_endian?
        [1].pack("I") == [1].pack("N")
      end

      def features
        []
      end

      def feature?(name)
        features.include?(name)
      end

      def arch_flag(arch)
        return "-mcpu=#{arch}" if ppc?

        "-march=#{arch}"
      end

      sig { returns(T::Boolean) }
      def in_rosetta2?
        false
      end
    end
  end

  class << self
    def cores_as_words
      case Hardware::CPU.cores
      when 1 then "single"
      when 2 then "dual"
      when 4 then "quad"
      when 6 then "hexa"
      when 8 then "octa"
      when 12 then "dodeca"
      else
        Hardware::CPU.cores
      end
    end

    def oldest_cpu(_version = nil)
      if Hardware::CPU.intel?
        if Hardware::CPU.is_64_bit?
          Hardware::CPU::INTEL_64BIT_OLDEST_CPU
        else
          :core
        end
      elsif Hardware::CPU.arm?
        if Hardware::CPU.is_64_bit?
          :armv8
        else
          :armv6
        end
      elsif Hardware::CPU.ppc? && Hardware::CPU.is_64_bit?
        if Hardware::CPU.little_endian?
          :ppc64le
        else
          :ppc64
        end
      else
        Hardware::CPU.family
      end
    end
    alias generic_oldest_cpu oldest_cpu

    # Returns a Rust flag to set the target CPU if necessary.
    # Defaults to nil.
    sig { returns(T.nilable(String)) }
    def rustflags_target_cpu
      # Rust already defaults to the oldest supported cpu for each target-triplet
      # so it's safe to ignore generic archs such as :armv6 here.
      # Rust defaults to apple-m1 since Rust 1.71 for aarch64-apple-darwin.
      @target_cpu ||= case (cpu = oldest_cpu)
      when :core
        :prescott
      when :native, :ivybridge, :sandybridge, :westmere, :nehalem, :core2
        cpu
      end
      return if @target_cpu.blank?

      "--codegen target-cpu=#{@target_cpu}"
    end
  end
end

require "extend/os/hardware"
