# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cleanup
      sig { returns(T::Boolean) }
      def use_system_ruby?
        return false if DinrusBrew::EnvConfig.force_vendor_ruby?

        ::DinrusBrew::EnvConfig.developer? && ENV["DINRUSBREW_USE_RUBY_FROM_PATH"].present?
      end
    end
  end
end

DinrusBrew::Cleanup.prepend(OS::Mac::Cleanup)
