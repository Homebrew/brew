# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Hardware
      module ClassMethods
        sig { params(version: T.nilable(MacOSVersion)).returns(Symbol) }
        def oldest_cpu(version = nil)
          version = if version
            MacOSVersion.new(version.to_s)
          else
            MacOS.version
          end
          if ::Hardware::CPU.arm64?
            :arm_vortex_tempest
          # This cannot use a newer CPU e.g. haswell because Rosetta 2 does not
          # support AVX instructions in bottles:
          #   https://github.com/Homebrew/homebrew-core/issues/67713
          elsif version >= :ventura
            :westmere
          elsif version >= :catalina
            :nehalem
          else
            super
          end
        end
      end
    end
  end
end

Hardware.singleton_class.prepend(OS::Mac::Hardware::ClassMethods)
