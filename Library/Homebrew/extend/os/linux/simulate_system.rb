# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module SimulateSystem
      sig { returns(T.nilable(Symbol)) }
      def os
        @os ||= T.let(nil, T.nilable(Symbol))
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

Homebrew::SimulateSystem.singleton_class.prepend(OS::Linux::SimulateSystem)
