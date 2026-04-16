# frozen_string_literal: true
# typed: strict

module T::Props
  module Private

    # Generates a specialized `serialize` implementation for a subclass of
    # T::Props::Serializable.
    #
    # The basic idea is that we analyze the props and for each prop, generate
    # the simplest possible logic as a block of Ruby source, so that we don't
    # pay the cost of supporting types like T:::Hash[CustomType, SubstructType]
    # when serializing a simple Integer. Then we join those together,
    # with a little shared logic to be able to detect when we get input keys
    # that don't match any prop.
    module SerializerGenerator
      extend T::Sig

      CAN_USE_SYMBOL_NAME = T.let(RUBY_VERSION >= "3.3.0", T::Boolean)

      sig do
        params(
          props: T::Hash[Symbol, T::Hash[Symbol, T.untyped]],
        )
        .returns(String)
        .checked(:never)
      end
      def self.generate(props)
        parts = props.filter_map do |prop, rules|
          next if rules[:dont_store]

          # All of these strings should already be validated (directly or
          # indirectly) in `validate_prop_name`, so we don't bother with a nice
          # error message, but we double check here to prevent a refactoring
          # from introducing a security vulnerability.
          raise unless T::Props::Decorator::SAFE_NAME.match?(CAN_USE_SYMBOL_NAME ? prop.name : prop.to_s)

          hash_key = rules.fetch(:serialized_form)
          raise unless T::Props::Decorator::SAFE_NAME.match?(hash_key)

          key = rules.fetch(:accessor_key)
          ivar_name = CAN_USE_SYMBOL_NAME ? key.name : key.to_s
          raise unless ivar_name.start_with?('@') && T::Props::Decorator::SAFE_ACCESSOR_KEY_NAME.match?(ivar_name)

          transformed_val = SerdeTransform.generate(
            T::Utils::Nilable.get_underlying_type_object(rules.fetch(:type_object)),
            SerdeTransform::Mode::SERIALIZE,
            ivar_name
          ) || ivar_name

          nil_asserter =
            if rules[:fully_optional]
              ''
            else
              "required_prop_missing_from_serialize(#{prop.inspect}) if strict"
            end

          # Don't serialize values that are nil to save space (both the
          # nil value itself and the field name in the serialized BSON
          # document)
          <<~RUBY
            if #{ivar_name}.nil?
              #{nil_asserter}
            else
              h[#{hash_key.inspect}] = #{transformed_val}
            end
          RUBY
        end

        <<~RUBY
          def __t_props_generated_serialize(strict)
            h = {}
            #{parts.join("\n\n")}
            h
          end
        RUBY
      end
    end
  end
end
