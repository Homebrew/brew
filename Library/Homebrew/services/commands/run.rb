# typed: strict
# frozen_string_literal: true

require "services/cli"

module Homebrew
  module Services
    module Commands
      module Run
        TRIGGERS = ["run"].freeze

        sig {
          params(
            targets:      T::Array[Services::FormulaWrapper],
            custom_plist: T.nilable(String),
            verbose:      T::Boolean,
          ).void
        }
        def self.run(targets, custom_plist, verbose:)
          Services::Cli.check!(targets)
          Services::Cli.run(targets, custom_plist, verbose:)
        end
      end
    end
  end
end
