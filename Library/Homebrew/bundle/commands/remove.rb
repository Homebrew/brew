# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/remover"

module Homebrew
  module Bundle
    module Commands
      module Remove
        def self.run(*args, type:, global:, file:)
          Homebrew::Bundle::Remover.remove(*args, type:, global:, file:)
        end
      end
    end
  end
end
