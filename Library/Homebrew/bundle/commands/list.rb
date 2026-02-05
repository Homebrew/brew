# typed: strict
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/lister"

module Homebrew
  module Bundle
    module Commands
      module List
        sig {
          params(global: T::Boolean, file: T.nilable(String), formulae: T::Boolean, casks: T::Boolean,
                 taps: T::Boolean, mas: T::Boolean, vscode: T::Boolean,
                 go: T::Boolean, cargo: T::Boolean, flatpak: T::Boolean).void
        }
        def self.run(global:, file:, formulae:, casks:, taps:, mas:, vscode:, go:, cargo:, flatpak:)
          parsed_entries = Brewfile.read(global:, file:).entries
          Homebrew::Bundle::Lister.list(
            parsed_entries,
            formulae:, casks:, taps:, mas:, vscode:, go:, cargo:, flatpak:,
          )
        end
      end
    end
  end
end
