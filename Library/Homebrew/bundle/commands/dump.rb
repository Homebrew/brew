# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/dumper"

module Homebrew
  module Bundle
    module Commands
      module Dump
        def self.run(global:, file:, describe:, force:, no_restart:, taps:, brews:, casks:, mas:, whalebrew:, vscode:)
          Homebrew::Bundle::Dumper.dump_brewfile(
            global:, file:, describe:, force:, no_restart:, taps:, brews:, casks:, mas:, whalebrew:, vscode:,
          )
        end
      end
    end
  end
end
