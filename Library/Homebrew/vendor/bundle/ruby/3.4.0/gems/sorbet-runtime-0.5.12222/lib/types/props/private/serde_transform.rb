# frozen_string_literal: true
# typed: strict

module T::Props
  module Private
    module SerdeTransform
      extend T::Sig

      class Serialize; end
      private_constant :Serialize
      class Deserialize; end
      private_constant :Deserialize
      ModeType = T.type_alias { T.any(Serialize, Deserialize) }
      private_constant :ModeType

      module Mode
        SERIALIZE = T.let(Serialize.new.freeze, Serialize)
        DESERIALIZE = T.let(Deserialize.new.freeze, Deserialize)
      end

      NO_TRANSFORM_TYPES = T.let(
        [TrueClass, FalseClass, NilClass, Symbol, String].freeze,
        T::Array[Module],
      )
      private_constant :NO_TRANSFORM_TYPES

      sig do
        params(
          type: T::Types::Base,
          mode: ModeType,
          varname: String,
        )
        .returns(T.nilable(String))
        .checked(:never)
      end
      def self.generate(type, mode, varname)
        case type
        when T::Types::TypedArray
          inner = generate(type.type, mode, 'v')
          if inner.nil?
            "#{varname}.dup"
          else
            "#{varname}.map {|v| #{inner}}"
          end
        when T::Types::TypedSet
          inner = generate(type.type, mode, 'v')
          if inner.nil?
            "#{varname}.dup"
          else
            "Set.new(#{varname}) {|v| #{inner}}"
          end
        when T::Types::TypedHash
          keys = generate(type.keys, mode, 'k')
          values = generate(type.values, mode, 'v')
          if keys && values
            "#{varname}.each_with_object({}) {|(k,v),h| h[#{keys}] = #{values}}"
          elsif keys
            "#{varname}.transform_keys {|k| #{keys}}"
          elsif values
            "#{varname}.transform_values {|v| #{values}}"
          else
            "#{varname}.dup"
          end
        when T::Types::Simple
          raw = type.raw_type
          if NO_TRANSFORM_TYPES.any? { |cls| raw <= cls }
            nil
          elsif raw <= Float
            case mode
            when Deserialize then "#{varname}.to_f"
            when Serialize then nil
            else T.absurd(mode)
            end
          elsif raw <= Numeric
            nil
          elsif raw < T::Props::Serializable
            handle_serializable_subtype(varname, raw, mode)
          elsif raw.singleton_class < T::Props::CustomType
            handle_custom_type(varname, T.unsafe(raw), mode)
          elsif T::Configuration.scalar_types.include?(raw.name)
            # It's a bit of a hack that this is separate from NO_TRANSFORM_TYPES
            # and doesn't check inheritance (like `T::Props::CustomType.scalar_type?`
            # does), but it covers the main use case (pay-server's custom `Boolean`
            # module) without either requiring `T::Configuration.scalar_types` to
            # accept modules instead of strings (which produces load-order issues
            # and subtle behavior changes) or eating the performance cost of doing
            # an inheritance check by manually crawling a class hierarchy and doing
            # string comparisons.
            nil
          else
            "T::Props::Utils.deep_clone_object(#{varname})"
          end
        when T::Types::Union
          non_nil_type = T::Utils.unwrap_nilable(type)
          if non_nil_type
            inner = generate(non_nil_type, mode, varname)
            if inner.nil?
              nil
            else
              "#{varname}.nil? ? nil : #{inner}"
            end
          elsif type.types.all? { |t| generate(t, mode, varname).nil? }
            # Handle, e.g., T::Boolean
            nil
          else
            # We currently deep_clone_object if the type was T.any(Integer, Float).
            # When we get better support for union types (maybe this specific
            # union type, because it would be a replacement for
            # Chalk::ODM::DeprecatedNumemric), we could opt to special case
            # this union to have no specific serde transform (the only reason
            # why Float has a special case is because round tripping through
            # JSON might normalize Floats to Integers)
            "T::Props::Utils.deep_clone_object(#{varname})"
          end
        when T::Types::Intersection
          dynamic_fallback = "T::Props::Utils.deep_clone_object(#{varname})"

          # Transformations for any members of the intersection type where we
          # know what we need to do and did not have to fall back to the
          # dynamic deep clone method.
          #
          # NB: This deliberately does include `nil`, which means we know we
          # don't need to do any transforming.
          inner_known = type.types
            .map { |t| generate(t, mode, varname) }
            .reject { |t| t == dynamic_fallback }
            .uniq

          if inner_known.size != 1
            # If there were no cases where we could tell what we need to do,
            # e.g. if this is `T.all(SomethingWeird, WhoKnows)`, just use the
            # dynamic fallback.
            #
            # If there were multiple cases and they weren't consistent, e.g.
            # if this is `T.all(String, T::Array[Integer])`, the type is probably
            # bogus/uninhabited, but use the dynamic fallback because we still
            # don't have a better option, and this isn't the place to raise that
            # error.
            dynamic_fallback
          else
            # This is probably something like `T.all(String, SomeMarker)` or
            # `T.all(SomeEnum, T.deprecated_enum(SomeEnum::FOO))` and we should
            # treat it like String or SomeEnum even if we don't know what to do
            # with the rest of the type.
            inner_known.first
          end
        when T::Types::Enum
          generate(T::Utils.lift_enum(type), mode, varname)
        else
          "T::Props::Utils.deep_clone_object(#{varname})"
        end
      end

      sig { params(varname: String, type: Module, mode: ModeType).returns(String).checked(:never) }
      private_class_method def self.handle_serializable_subtype(varname, type, mode)
        case mode
        when Serialize
          "#{varname}.serialize(strict)"
        when Deserialize
          type_name = T.must(module_name(type))
          "#{type_name}.from_hash(#{varname})"
        else
          T.absurd(mode)
        end
      end

      sig { params(varname: String, type: Module, mode: ModeType).returns(String).checked(:never) }
      private_class_method def self.handle_custom_type(varname, type, mode)
        case mode
        when Serialize
          "T::Props::CustomType.checked_serialize(#{varname})"
        when Deserialize
          type_name = T.must(module_name(type))
          "#{type_name}.deserialize(#{varname})"
        else
          T.absurd(mode)
        end
      end

      sig { params(type: Module).returns(T.nilable(String)).checked(:never) }
      private_class_method def self.module_name(type)
        T::Configuration.module_name_mangler.call(type)
      end
    end
  end
end
