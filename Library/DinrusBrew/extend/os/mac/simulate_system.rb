# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module SimulateSystem
      sig { returns(T::Boolean) }
      def simulating_or_running_on_macos?
        return true if DinrusBrew::SimulateSystem.os.blank?

        [:macos, *MacOSVersion::SYMBOLS.keys].include?(DinrusBrew::SimulateSystem.os)
      end

      sig { returns(Symbol) }
      def current_os
        ::DinrusBrew::SimulateSystem.os || MacOS.version.to_sym
      end
    end
  end
end

DinrusBrew::SimulateSystem.singleton_class.prepend(OS::Mac::SimulateSystem)
