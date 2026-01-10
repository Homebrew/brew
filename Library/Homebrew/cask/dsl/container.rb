# typed: strict
# frozen_string_literal: true

require "unpack_strategy"

module Cask
  class DSL
    # Class corresponding to the `container` stanza.
    class Container
      sig { returns(T.nilable(String)) }
      attr_accessor :nested

      sig { returns(T.nilable(Symbol)) }
      attr_accessor :type

      sig { params(nested: T.nilable(String), type: T.nilable(Symbol)).void }
      def initialize(nested: nil, type: nil)
        @nested = T.let(nested, T.nilable(String))
        @type = T.let(type, T.nilable(Symbol))

        return if type.nil?
        return unless UnpackStrategy.from_type(type).nil?

        raise "invalid container type: #{type.inspect}"
      end

      sig { returns(T::Hash[Symbol, T.nilable(T.any(String, Symbol))]) }
      def pairs
        instance_variables.to_h { |ivar| [ivar[1..].to_sym, instance_variable_get(ivar)] }.compact
      end

      sig { returns(String) }
      def to_yaml
        pairs.to_yaml
      end

      sig { returns(String) }
      def to_s = pairs.inspect
    end
  end
end
