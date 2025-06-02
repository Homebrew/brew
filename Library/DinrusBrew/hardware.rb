# typed: strict
# frozen_string_literal: true

require "utils/popen"

# Helper module for querying hardware information.
module Hardware
  # Helper module for querying CPU information.
  class CPU
    INTEL_32BIT_ARCHS = [:i386].freeze
    INTEL_64BIT_ARCHS = [:x86_64].freeze
    INTEL_ARCHS       = T.let((INTEL_32BIT_ARCHS + INTEL_64BIT_ARCHS).freeze, T::Array[Symbol])
    PPC_32BIT_ARCHS   = [:ppc, :ppc32, :ppc7400, :ppc7450, :ppc970].freeze
    PPC_64BIT_ARCHS   = [:ppc64, :ppc64le, :ppc970].freeze
    PPC_ARCHS         = T.let((PPC_32BIT_ARCHS + PPC_64BIT_ARCHS).freeze, T::Array[Symbol])
    ARM_64BIT_ARCHS   = [:arm64, :aarch64].freeze
    ARM_ARCHS         = ARM_64BIT_ARCHS
    ALL_ARCHS = T.let([
      *INTEL_ARCHS,
      *PPC_ARCHS,
      *ARM_ARCHS,
    ].freeze, T::Array[Symbol])

    INTEL_64BIT_OLDEST_CPU = :core2

    class << self
      sig { returns(T::Hash[Symbol, String]) }
      def optimization_flags
        @optimization_flags ||= T.let({
          dunno:              "",
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
        }.freeze, T.nilable(T::Hash[Symbol, String]))
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

      sig { returns(Symbol) }
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

      sig { returns(Integer) }
      def cores
        return @cores if @cores

        @cores = Utils.popen_read("getconf", "_NPROCESSORS_ONLN").chomp.to_i
        @cores = T.let(1, T.nilable(Integer)) unless $CHILD_STATUS.success?
        @cores
      end

      sig { returns(T.nilable(Integer)) }
      def bits
        @bits ||= T.let(case RUBY_PLATFORM
        when /x86_64/, /ppc64|powerpc64/, /aarch64|arm64/ then 64
        when /i\d86/, /ppc/, /arm/ then 32
        end, T.nilable(Integer))
      end

      sig { returns(T::Boolean) }
      def sse4?
        RUBY_PLATFORM.to_s.include?("x86_64")
      end

      sig { returns(T::Boolean) }
      def is_32_bit?
        bits == 32
      end

      sig { returns(T::Boolean) }
      def is_64_bit?
        bits == 64
      end

      sig { returns(T::Boolean) }
      def intel?
        type == :intel
      end

      sig { returns(T::Boolean) }
      def ppc?
        type == :ppc
      end

      sig { returns(T::Boolean) }
      def ppc32?
        ppc? && is_32_bit?
      end

      sig { returns(T::Boolean) }
      def ppc64le?
        ppc? && is_64_bit? && little_endian?
      end

      sig { returns(T::Boolean) }
      def ppc64?
        ppc? && is_64_bit? && big_endian?
      end

      # Check whether the CPU architecture is ARM.
      #
      # @api internal
      sig { returns(T::Boolean) }
      def arm?
        type == :arm
      end

      sig { returns(T::Boolean) }
      def little_endian?
        !big_endian?
      end

      sig { returns(T::Boolean) }
      def big_endian?
        [1].pack("I") == [1].pack("N")
      end

      sig { returns(FalseClass) }
      def virtualized?
        false
      end

      sig { returns(T::Array[Symbol]) }
      def features
        []
      end

      sig { params(name: Symbol).returns(T::Boolean) }
      def feature?(name)
        features.include?(name)
      end

      sig { params(arch: T.any(String, Symbol)).returns(String) }
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
    sig { returns(String) }
    def cores_as_words
      case Hardware::CPU.cores
      when 1 then "single"
      when 2 then "dual"
      when 4 then "quad"
      when 6 then "hexa"
      when 8 then "octa"
      when 10 then "deca"
      when 12 then "dodeca"
      else
        Hardware::CPU.cores.to_s
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
    sig { params(arch: Symbol).returns(T.nilable(String)) }
    def rustflags_target_cpu(arch)
      # Rust already defaults to the oldest supported cpu for each target-triplet
      # so it's safe to ignore generic archs such as :armv6 here.
      # Rust defaults to apple-m1 since Rust 1.71 for aarch64-apple-darwin.
      @target_cpu ||= T.let(case arch
      when :core
        :prescott
      when :native, :ivybridge, :sandybridge, :westmere, :nehalem, :core2
        arch
      end, T.nilable(Symbol))
      return if @target_cpu.blank?

      "--codegen target-cpu=#{@target_cpu}"
    end
  end
end

require "extend/os/hardware"
