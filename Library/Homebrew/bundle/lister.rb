# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/extensions"

module Homebrew
  module Bundle
    module Lister
      sig {
        params(entries: T::Array[Object], formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean,
               extension_types: Homebrew::Bundle::ExtensionTypes,
               extra_extension_types: Homebrew::Bundle::ExtensionTypes).void.checked(:never)
      }
      def self.list(entries, formulae:, casks:, taps:, extension_types: {}, **extra_extension_types)
        # TODO: Remove `extra_extension_types` once all callers pass a single
        # `extension_types:` hash instead of legacy per-extension keywords.
        merged_extension_types = T.cast(extension_types.merge(extra_extension_types),
                                        Homebrew::Bundle::ExtensionTypes)
        entries.each do |entry|
          entry = T.cast(entry, Dsl::Entry)
          puts entry.name if show?(entry.type, formulae:, casks:, taps:, extension_types: merged_extension_types)
        end
      end

      sig {
        params(type: Symbol, formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean,
               extension_types: Homebrew::Bundle::ExtensionTypes)
          .returns(T::Boolean)
      }
      private_class_method def self.show?(type, formulae:, casks:, taps:, extension_types:)
        return true if formulae && type == :brew
        return true if casks && type == :cask
        return true if taps && type == :tap
        return true if extension_types.fetch(type, false)

        false
      end
    end
  end
end
