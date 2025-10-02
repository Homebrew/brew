# typed: strict
# frozen_string_literal: true

require "bundle/dumper"

module Homebrew
  module Bundle
    module Commands
      module Dump
        sig {
          params(global: T::Boolean, file: T.nilable(String), describe: T::Boolean, force: T::Boolean,
                 no_restart: T::Boolean, taps: T::Boolean, formulae: T::Boolean, casks: T::Boolean,
                 mas: T::Boolean, whalebrew: T::Boolean, vscode: T::Boolean, packages: T::Boolean).void
        }
        def self.run(global:, file:, describe:, force:, no_restart:, taps:, formulae:, casks:, mas:, whalebrew:,
                     vscode:, packages:)
          Homebrew::Bundle::Dumper.dump_brewfile(
            global:, file:, describe:, force:, no_restart:, taps:, formulae:, casks:, mas:, whalebrew:, vscode:,
            packages:
          )
        end
      end
    end
  end
end
