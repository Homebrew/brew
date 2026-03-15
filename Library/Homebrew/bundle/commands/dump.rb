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
                 extension_types: Homebrew::Bundle::ExtensionTypes,
                 extra_extension_types: Homebrew::Bundle::ExtensionTypes).void.checked(:never)
        }
        def self.run(global:, file:, describe:, force:, no_restart:, taps:, formulae:, casks:, extension_types: {},
                     **extra_extension_types)
          # TODO: Remove `extra_extension_types` once all callers pass a single
          # `extension_types:` hash instead of legacy per-extension keywords.
          Homebrew::Bundle::Dumper.dump_brewfile(
            global:, file:, describe:, force:, no_restart:, taps:, formulae:, casks:, extension_types:,
            **extra_extension_types
          )
        end
      end
    end
  end
end
