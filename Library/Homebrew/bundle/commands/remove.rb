# typed: strict
# frozen_string_literal: true

require "bundle/remover"

module Homebrew
  module Bundle
    module Commands
      module Remove
        sig { params(args: String, type: Symbol, global: T::Boolean, file: T.nilable(String)).void }
        def self.run(*args, type:, global:, file:)
          Homebrew::Bundle::Remover.remove(*args, type:, global:, file:)
        end
      end
    end
  end
end
