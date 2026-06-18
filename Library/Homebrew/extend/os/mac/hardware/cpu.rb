# typed: strict
# frozen_string_literal: true

require "macho"

module OS
  module Mac
    module Hardware
      module CPU
        module ClassMethods
          extend T::Helpers

          # These methods use info spewed out by sysctl.
          # Look in <mach/machine.h> for decoding info.
          sig { returns(Symbol) }
          def type
            case ::Hardware::CPU.sysctl_int("hw.cputype")
            when MachO::Headers::CPU_TYPE_I386
              :intel
            when MachO::Headers::CPU_TYPE_ARM64
              :arm
            else
              super
            end
          end

          sig { returns(Symbol) }
          def family
            if ::Hardware::CPU.arm?
              ::Hardware::CPU.arm_family
            elsif ::Hardware::CPU.intel?
              ::Hardware::CPU.intel_family
            else
              :dunno
            end
          end

          # True when running under an Intel-based shell via Rosetta 2 on an
          # Apple Silicon Mac. This can be detected via seeing if there's a
          # conflict between what `uname` reports and the underlying `sysctl` flags,
          # since the `sysctl` flags don't change behaviour under Rosetta 2.
          sig { returns(T::Boolean) }
          def in_rosetta2?
            ::Hardware::CPU.sysctl_bool!("sysctl.proc_translated")
          end

          sig { returns(T::Array[Symbol]) }
          def features
            @features ||= T.let(::Hardware::CPU.sysctl_n(
              "machdep.cpu.features",
              "machdep.cpu.extfeatures",
              "machdep.cpu.leaf7_features",
            ).split.map { |s| s.downcase.to_sym }, T.nilable(T::Array[Symbol]))
          end

          sig { returns(T::Boolean) }
          def sse4?
            ::Hardware::CPU.sysctl_bool!("hw.optional.sse4_1")
          end
        end
      end
    end
  end
end

Hardware::CPU.singleton_class.prepend(OS::Mac::Hardware::CPU::ClassMethods)
require "extend/os/mac/hardware/cpu/hardware"
