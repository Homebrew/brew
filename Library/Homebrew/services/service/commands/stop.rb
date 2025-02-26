# typed: strict
# frozen_string_literal: true

module Service
  module Commands
    module Stop
      TRIGGERS = %w[stop unload terminate term t u].freeze

      sig {
        params(targets: T::Array[Service::FormulaWrapper], verbose: T::Boolean, no_wait: T::Boolean,
               max_wait: Float).void
      }
      def self.run(targets, verbose:, no_wait:, max_wait:)
        Homebrew::Cmd::Services.check(targets) &&
          Homebrew::Cmd::Services.stop(targets, verbose:, no_wait:, max_wait:)
      end
    end
  end
end
