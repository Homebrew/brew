# typed: strict
# frozen_string_literal: true

require "delegate"
require "extend/hash/keys"
require "utils/output"

module Cask
  class DSL
    # Class corresponding to the `conflicts_with` stanza.
    class ConflictsWith < SimpleDelegator
      VALID_KEYS = [:cask].freeze

      ODISABLED_KEYS = [
        :formula,
        :macos,
        :arch,
        :x11,
        :java,
      ].freeze

      sig { params(options: T.anything).void }
      def initialize(**options)
        options.assert_valid_keys(*VALID_KEYS, *ODISABLED_KEYS)

        options.keys.intersection(ODISABLED_KEYS).each do |key|
          ::Utils::Output.odisabled "conflicts_with #{key}:"
        end

        conflicts = options.transform_values { |v| Set.new(Kernel.Array(v)) }
        conflicts.default = Set.new

        super(conflicts)
      end

      sig { params(generator: T.anything).returns(String) }
      def to_json(generator)
        __getobj__.transform_values(&:to_a).to_json(generator)
      end
    end
  end
end
