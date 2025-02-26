# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Stop
      TRIGGERS = %w[stop unload terminate term t u].freeze

      sig {
        params(targets:  T::Array[Service::FormulaWrapper],
               verbose:  T.nilable(T::Boolean),
               no_wait:  T.nilable(T::Boolean),
               max_wait: T.nilable(Float)).void
      }
      def self.run(targets, verbose:, no_wait:, max_wait:)
        Service::ServicesCli.check(targets)
        Service::ServicesCli.stop(targets, verbose:, no_wait:, max_wait:)
      end
    end
  end
end
