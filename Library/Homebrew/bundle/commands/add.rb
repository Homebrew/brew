# typed: strict
# frozen_string_literal: true

require "bundle/adder"

module Homebrew
  module Bundle
    module Commands
      module Add
        sig { params(args: String, type: Symbol, global: T::Boolean, file: T.nilable(String)).void }
        def self.run(*args, type:, global:, file:)
          Homebrew::Bundle::Adder.add(*args, type:, global:, file:)
        end
      end
    end
  end
end
