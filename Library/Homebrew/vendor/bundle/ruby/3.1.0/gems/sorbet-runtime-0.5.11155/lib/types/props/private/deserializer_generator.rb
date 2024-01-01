# frozen_string_literal: true
# typed: strict

module T::Props
  module Private

    # Generates a specialized `deserialize` implementation for a subclass of
    # T::Props::Serializable.
    #
    # The basic idea is that we analyze the props and for each prop, generate
    # the simplest possible logic as a block of Ruby source, so that we don't
    # pay the cost of supporting types like T:::Hash[CustomType, SubstructType]
    # when deserializing a simple Integer. Then we join those together,
    # with a little shared logic to be able to detect when we get input keys
    # that don't match any prop.
    module DeserializerGenerator
      extend T::Sig

      # Generate a method that takes a T::Hash[String, T.untyped] representing
      # serialized props, sets instance variables for each prop found in the
      # input, and returns the count of we props set (which we can use to check
      # for unexpected input keys with minimal effect on the fast path).
      sig do
        params(
          props: T::Hash[Symbol, T::Hash[Symbol, T.untyped]],
          defaults: T::Hash[Symbol, T::Props::Private::ApplyDefault],
        )
        .returns(String)
        .checked(:never)
      end
      def self.generate(props, defaults)
        stored_props = props.reject {|_, rules| rules[:dont_store]}
        parts = stored_props.map do |prop, rules|
          # All of these strings should already be validated (directly or
          # indirectly) in `validate_prop_name`, so we don't bother with a nice
          # error message, but we double check here to prevent a refactoring
          # from introducing a security vulnerability.
          raise unless T::Props::Decorator::SAFE_NAME.match?(prop.to_s)

          hash_key = rules.fetch(:serialized_form)
          raise unless T::Props::Decorator::SAFE_NAME.match?(hash_key)

          ivar_name = rules.fetch(:accessor_key).to_s
          raise unless ivar_name.start_with?('@') && T::Props::Decorator::SAFE_NAME.match?(ivar_name[1..-1])

          transformation = SerdeTransform.generate(
            T::Utils::Nilable.get_underlying_type_object(rules.fetch(:type_object)),
            SerdeTransform::Mode::DESERIALIZE,
            'val'
          )
          transformed_val = if transformation
            # Rescuing exactly NoMethodError is intended as a temporary hack
            # to preserve the semantics from before codegen. More generally
            # we are inconsistent about typechecking on deser and need to decide
            # our strategy here.
            <<~RUBY
              begin
                #{transformation}
              rescue NoMethodError => e
                raise_deserialization_error(
                  #{prop.inspect},
                  val,
                  e,
                )
                val
              end
            RUBY
          else
            'val'
          end

          nil_handler = generate_nil_handler(
            prop: prop,
            serialized_form: hash_key,
            default: defaults[prop],
            nilable_type: T::Props::Utils.optional_prop?(rules),
            raise_on_nil_write: !!rules[:raise_on_nil_write],
          )

          <<~RUBY
            val = hash[#{hash_key.inspect}]
            #{ivar_name} = if val.nil?
              found -= 1 unless hash.key?(#{hash_key.inspect})
              #{nil_handler}
            else
              #{transformed_val}
            end
          RUBY
        end

        <<~RUBY
          def __t_props_generated_deserialize(hash)
            found = #{stored_props.size}
            #{parts.join("\n\n")}
            found
          end
        RUBY
      end

      # This is very similar to what we do in ApplyDefault, but has a few
      # key differences that mean we don't just re-use the code:
      #
      # 1. Where the logic in construction is that we generate a default
      #    if & only if the prop key isn't present in the input, here we'll
      #    generate a default even to override an explicit nil, but only
      #    if the prop is actually required.
      # 2. Since we're generating raw Ruby source, we can remove a layer
      #    of indirection for marginally better performance; this seems worth
      #    it for the common cases of literals and empty arrays/hashes.
      # 3. We need to care about the distinction between `raise_on_nil_write`
      #    and actually non-nilable, where new-instance construction doesn't.
      #
      # So we fall back to ApplyDefault only when one of the cases just
      # mentioned doesn't apply.
      sig do
        params(
          prop: Symbol,
          serialized_form: String,
          default: T.nilable(ApplyDefault),
          nilable_type: T::Boolean,
          raise_on_nil_write: T::Boolean,
        )
        .returns(String)
        .checked(:never)
      end
      private_class_method def self.generate_nil_handler(
        prop:,
        serialized_form:,
        default:,
        nilable_type:,
        raise_on_nil_write:
      )
        if !nilable_type
          case default
          when NilClass
            "self.class.decorator.raise_nil_deserialize_error(#{serialized_form.inspect})"
          when ApplyPrimitiveDefault
            literal = default.default
            case literal
            when String, Integer, Symbol, Float, TrueClass, FalseClass, NilClass
              literal.inspect
            else
              "self.class.decorator.props_with_defaults.fetch(#{prop.inspect}).default"
            end
          when ApplyEmptyArrayDefault
            '[]'
          when ApplyEmptyHashDefault
            '{}'
          else
            "self.class.decorator.props_with_defaults.fetch(#{prop.inspect}).default"
          end
        elsif raise_on_nil_write
          "required_prop_missing_from_deserialize(#{prop.inspect})"
        else
          'nil'
        end
      end
    end
  end
end
