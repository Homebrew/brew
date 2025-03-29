# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/brewfile"
require "bundle/lister"

module Homebrew
  module Bundle
    module Commands
      module List
        def self.run(global:, file:, brews:, casks:, taps:, mas:, whalebrew:, vscode:)
          parsed_entries = Brewfile.read(global:, file:).entries
          Homebrew::Bundle::Lister.list(
            parsed_entries,
            brews:, casks:, taps:, mas:, whalebrew:, vscode:,
          )
        end
      end
    end
  end
end
