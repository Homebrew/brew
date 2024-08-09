# typed: true # This cannot be `# typed: strict` due to the use of `undef`.
# frozen_string_literal: true

module Homebrew
  class SimulateSystem
    class << self
      undef os
      undef simulating_or_running_on_linux?
      undef current_os

      sig { returns(T.nilable(Symbol)) }
      def os
        return :macos if @os.blank? && Homebrew::EnvConfig.simulate_macos_on_linux?

        @os
      end

      sig { returns(T::Boolean) }
      def simulating_or_running_on_linux?
        os.blank? || os == :linux
      end

      sig { returns(Symbol) }
      def current_os
        os || :linux
      end
    end
  end
end
