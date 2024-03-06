# typed: true
# frozen_string_literal: true

require "delegate"
require "extend/hash/keys"

module Cask
  class DSL
    # Class corresponding to the `conflicts_with` stanza.
    class ConflictsWith < SimpleDelegator
      VALID_KEYS = [
        :formula,
        :cask,
        :macos,
        :arch,
        :x11,
        :java,
      ].freeze

      def initialize(**options)
        options.assert_valid_keys(*VALID_KEYS)

        conflicts = options.transform_values { |v| Set.new(Kernel.Array(v)) }
        conflicts.default = Set.new

        super(conflicts)
      end

      def to_json(generator)
        __getobj__.transform_values(&:to_a).to_json(generator)
      end
    end
  end
end
