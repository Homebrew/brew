# frozen_string_literal: true
# typed: false

module T::Props::TypeValidation
  include T::Props::Plugin

  BANNED_TYPES = [Object, BasicObject, Kernel].freeze

  class UnderspecifiedType < ArgumentError; end

  module DecoratorMethods
    extend T::Sig

    sig { params(key: Symbol).returns(T::Boolean).checked(:never) }
    def valid_rule_key?(key)
      super || key == :DEPRECATED_underspecified_type
    end

    # checked(:never) - Rules hash is expensive to check
    sig do
      params(
        name: T.any(Symbol, String),
        _cls: T::Module[T.anything],
        rules: T::Hash[Symbol, T.untyped],
        type: T.any(T::Types::Base, T::Module[T.anything])
      )
      .void
      .checked(:never)
    end
    def prop_validate_definition!(name, _cls, rules, type)
      super

      if !rules[:DEPRECATED_underspecified_type]
        validate_type(type, name)
      elsif rules[:DEPRECATED_underspecified_type] && find_invalid_subtype(type).nil?
        raise ArgumentError.new("DEPRECATED_underspecified_type set unnecessarily for #{@class.name}.#{name} - #{type} is a valid type")
      end
    end

    sig do
      params(
        type: T::Types::Base,
        field_name: T.any(Symbol, String),
      )
      .void
      .checked(:never)
    end
    private def validate_type(type, field_name)
      if (invalid_subtype = find_invalid_subtype(type))
        raise UnderspecifiedType.new(type_error_message(invalid_subtype, field_name, type))
      end
    end

    # Returns an invalid type, if any, found in the given top-level type.
    # This might be the type itself, if it is e.g. "Object", or might be
    # a subtype like the type of the values of a typed hash.
    #
    # If the type is fully valid, returns nil.
    #
    # checked(:never) - called potentially many times recursively
    sig { params(type: T::Types::Base).returns(T.nilable(T::Types::Base)).checked(:never) }
    private def find_invalid_subtype(type)
      case type
      when T::Types::TypedEnumerable
        find_invalid_subtype(type.type)
      when T::Types::FixedHash
        type.types.values.map { |subtype| find_invalid_subtype(subtype) }.compact.first
      when T::Types::Union, T::Types::FixedArray
        # `T.any` is valid if all of the members are valid
        type.types.map { |subtype| find_invalid_subtype(subtype) }.compact.first
      when T::Types::Intersection
        # `T.all` is valid if at least one of the members is valid
        invalid = type.types.map { |subtype| find_invalid_subtype(subtype) }.compact
        if invalid.length == type.types.length
          invalid.first
        else
          nil
        end
      when T::Types::Enum, T::Types::ClassOf
        nil
      when T::Private::Types::TypeAlias
        find_invalid_subtype(type.aliased_type)
      when T::Types::Simple
        # TODO Could we manage to define a whitelist, consisting of something
        # like primitives, subdocs, DataInterfaces, and collections/enums/unions
        # thereof?
        if BANNED_TYPES.include?(type.raw_type)
          type
        else
          nil
        end
      else
        type
      end
    end

    sig do
      params(
        type: T::Types::Base,
        field_name: T.any(Symbol, String),
        orig_type: T::Types::Base,
      )
      .returns(String)
    end
    private def type_error_message(type, field_name, orig_type)
      msg_prefix = "#{@class.name}.#{field_name}: #{orig_type} is invalid in prop definition"
      if type == orig_type
        "#{msg_prefix}. Please choose a more specific type (T.untyped and ~equivalents like Object are banned)."
      else
        "#{msg_prefix}. Please choose a subtype more specific than #{type} (T.untyped and ~equivalents like Object are banned)."
      end
    end
  end
end
