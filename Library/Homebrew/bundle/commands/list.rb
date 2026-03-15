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
                 taps: T::Boolean, extension_types: Homebrew::Bundle::ExtensionTypes,
                 extra_extension_types: Homebrew::Bundle::ExtensionTypes).void.checked(:never)
        }
        def self.run(global:, file:, formulae:, casks:, taps:, extension_types: {}, **extra_extension_types)
          # TODO: Remove `extra_extension_types` once all callers pass a single
          # `extension_types:` hash instead of legacy per-extension keywords.
          parsed_entries = Brewfile.read(global:, file:).entries
          Homebrew::Bundle::Lister.list(
            parsed_entries, formulae:, casks:, taps:, extension_types:, **extra_extension_types
          )
        end
      end
    end
  end
end
