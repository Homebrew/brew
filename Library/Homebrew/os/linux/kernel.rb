# typed: true
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying Linux kernel information.
    #
    # @api private
    module Kernel
      module_function

      sig { returns(Version) }
      def minimum_version
        Version.new "3.2"
      end

      def below_minimum_version?
        OS.kernel_version < minimum_version
      end
    end
  end
end
