# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/extensions"

module Homebrew
  module Bundle
    module Lister
      sig {
        params(entries: T::Array[Dsl::Entry], formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean,
               extension_types: Homebrew::Bundle::ExtensionTypes).void
      }
      def self.list(entries, formulae:, casks:, taps:, extension_types: {})
        entries.each do |entry|
          puts entry.name if show?(entry.type, formulae:, casks:, taps:, extension_types:)
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
