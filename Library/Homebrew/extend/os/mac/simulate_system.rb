# typed: true
# frozen_string_literal: true

module Homebrew
  class SimulateSystem
    class << self
      undef simulating_or_running_on_macos?
      undef current_os

      sig { returns(T::Boolean) }
      def simulating_or_running_on_macos?
        os.blank? || [:macos, *MacOSVersion::SYMBOLS.keys].include?(os)
      end

      sig { returns(Symbol) }
      def current_os
        os || MacOS.version.to_sym
      end
    end
  end
end
