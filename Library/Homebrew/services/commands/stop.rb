# typed: strict
# frozen_string_literal: true

require "services/cli"

module Homebrew
  module Services
    module Commands
      module Stop
        TRIGGERS = %w[stop unload terminate term t u].freeze

        sig {
          params(
            targets:  T::Array[Services::FormulaWrapper],
            verbose:  T::Boolean,
            no_wait:  T::Boolean,
            max_wait: T.nilable(Float),
          ).void
        }
        def self.run(targets, verbose:, no_wait:, max_wait:)
          Services::Cli.check(targets)
          Services::Cli.stop(targets, verbose:, no_wait:, max_wait:)
        end
      end
    end
  end
end
