# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module SharedEnvExtension
      extend T::Helpers

      requires_ancestor { ::SharedEnvExtension }

      sig { returns(Symbol) }
      def effective_arch
        if build_bottle && (bottle_arch = self.bottle_arch)
          bottle_arch.to_sym
        elsif build_bottle
          ::Hardware.oldest_cpu
        elsif ::Hardware::CPU.intel? || ::Hardware::CPU.arm?
          :native
        else
          :dunno
        end
      end
    end
  end
end

SharedEnvExtension.prepend(OS::Linux::SharedEnvExtension)
