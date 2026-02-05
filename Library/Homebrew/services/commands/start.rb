# typed: strict
# frozen_string_literal: true

require "services/cli"

module Homebrew
  module Services
    module Commands
      module Start
        TRIGGERS = %w[start launch load s l].freeze

        sig {
          params(
            targets:      T::Array[Services::FormulaWrapper],
            custom_plist: T.nilable(String),
            verbose:      T::Boolean,
          ).void
        }
        def self.run(targets, custom_plist, verbose:)
          Services::Cli.check!(targets)
          Services::Cli.start(targets, custom_plist, verbose:)
        end
      end
    end
  end
end
