# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Commands
      module Remove
        module_function

        def run(*args, type:, global:, file:)
          Homebrew::Bundle::Remover.remove(*args, type:, global:, file:)
        end
      end
    end
  end
end
