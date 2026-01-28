# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying Linux kernel information.
    module Kernel
      module_function

      sig { returns(Version) }
      def minimum_version
        Version.new "3.2"
      end

      sig { returns(T::Boolean) }
      def below_minimum_version?
        OS.kernel_version < minimum_version
      end
    end
  end
end
