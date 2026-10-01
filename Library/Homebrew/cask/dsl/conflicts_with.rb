# typed: strict
# frozen_string_literal: true

require "utils/data"

require "delegate"
require "extend/hash/keys"
require "utils/output"

module Cask
  class DSL
    # Class corresponding to the `conflicts_with` stanza.
    class ConflictsWith < SimpleDelegator
      VALID_KEYS = [:cask].freeze

      sig { params(options: T.anything).void }
      def initialize(**options)
        ::Utils::Data.assert_valid_keys(options, *VALID_KEYS)

        conflicts = options.transform_values { |v| Set.new(Kernel.Array(v)) }
        conflicts.default = Set.new

        super(conflicts)
      end

      sig { params(other: ConflictsWith).returns(T.self_type) }
      def merge!(other)
        other.to_h.each { |key, values| __getobj__[key] |= Set.new(values) }
        self
      end

      sig { returns(T::Hash[Symbol, T::Array[String]]) }
      def to_h
        __getobj__.transform_values(&:to_a)
      end

      sig { params(generator: T.anything).returns(String) }
      def to_json(generator)
        to_h.to_json(generator)
      end
    end
  end
end
