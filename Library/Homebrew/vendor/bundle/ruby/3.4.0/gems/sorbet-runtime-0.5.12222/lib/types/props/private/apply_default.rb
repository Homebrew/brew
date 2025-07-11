# frozen_string_literal: true
# typed: strict

module T::Props
  module Private
    class ApplyDefault
      extend T::Sig
      extend T::Helpers
      abstract!

      # checked(:never) - O(object construction x prop count)
      sig { returns(SetterFactory::SetterProc).checked(:never) }
      attr_reader :setter_proc

      # checked(:never) - We do this with `T.let` instead
      sig { params(accessor_key: Symbol, setter_proc: SetterFactory::SetterProc).void.checked(:never) }
      def initialize(accessor_key, setter_proc)
        @accessor_key = T.let(accessor_key, Symbol)
        @setter_proc = T.let(setter_proc, SetterFactory::SetterProc)
      end

      # checked(:never) - O(object construction x prop count)
      sig { abstract.returns(T.untyped).checked(:never) }
      def default; end

      # checked(:never) - O(object construction x prop count)
      sig { abstract.params(instance: T.all(T::Props::Optional, Object)).void.checked(:never) }
      def set_default(instance); end

      NO_CLONE_TYPES = T.let([TrueClass, FalseClass, NilClass, Symbol, Numeric, T::Enum].freeze, T::Array[Module])

      # checked(:never) - Rules hash is expensive to check
      sig { params(cls: Module, rules: T::Hash[Symbol, T.untyped]).returns(T.nilable(ApplyDefault)).checked(:never) }
      def self.for(cls, rules)
        accessor_key = rules.fetch(:accessor_key)
        setter = rules.fetch(:setter_proc)

        if rules.key?(:factory)
          ApplyDefaultFactory.new(cls, rules.fetch(:factory), accessor_key, setter)
        elsif rules.key?(:default)
          default = rules.fetch(:default)
          case default
          when *NO_CLONE_TYPES
            return ApplyPrimitiveDefault.new(default, accessor_key, setter)
          when String
            if default.frozen?
              return ApplyPrimitiveDefault.new(default, accessor_key, setter)
            end
          when Array
            if default.empty? && default.class == Array
              return ApplyEmptyArrayDefault.new(accessor_key, setter)
            end
          when Hash
            if default.empty? && default.default.nil? && T.unsafe(default).default_proc.nil? && default.class == Hash
              return ApplyEmptyHashDefault.new(accessor_key, setter)
            end
          end

          ApplyComplexDefault.new(default, accessor_key, setter)
        else
          nil
        end
      end
    end

    class ApplyFixedDefault < ApplyDefault
      abstract!

      # checked(:never) - We do this with `T.let` instead
      sig { params(default: BasicObject, accessor_key: Symbol, setter_proc: SetterFactory::SetterProc).void.checked(:never) }
      def initialize(default, accessor_key, setter_proc)
        # FIXME: Ideally we'd check here that the default is actually a valid
        # value for this field, but existing code relies on the fact that we don't.
        #
        # :(
        #
        # setter_proc.call(default)
        @default = T.let(default, BasicObject)
        super(accessor_key, setter_proc)
      end

      # checked(:never) - O(object construction x prop count)
      sig { override.params(instance: T.all(T::Props::Optional, Object)).void.checked(:never) }
      def set_default(instance)
        instance.instance_variable_set(@accessor_key, default)
      end
    end

    class ApplyPrimitiveDefault < ApplyFixedDefault
      # checked(:never) - O(object construction x prop count)
      sig { override.returns(T.untyped).checked(:never) }
      attr_reader :default
    end

    class ApplyComplexDefault < ApplyFixedDefault
      # checked(:never) - O(object construction x prop count)
      sig { override.returns(T.untyped).checked(:never) }
      def default
        T::Props::Utils.deep_clone_object(@default)
      end
    end

    # Special case since it's so common, and a literal `[]` is meaningfully
    # faster than falling back to ApplyComplexDefault or even calling
    # `some_empty_array.dup`
    class ApplyEmptyArrayDefault < ApplyDefault
      # checked(:never) - O(object construction x prop count)
      sig { override.params(instance: T.all(T::Props::Optional, Object)).void.checked(:never) }
      def set_default(instance)
        instance.instance_variable_set(@accessor_key, [])
      end

      # checked(:never) - O(object construction x prop count)
      sig { override.returns(T::Array[T.untyped]).checked(:never) }
      def default
        []
      end
    end

    # Special case since it's so common, and a literal `{}` is meaningfully
    # faster than falling back to ApplyComplexDefault or even calling
    # `some_empty_hash.dup`
    class ApplyEmptyHashDefault < ApplyDefault
      # checked(:never) - O(object construction x prop count)
      sig { override.params(instance: T.all(T::Props::Optional, Object)).void.checked(:never) }
      def set_default(instance)
        instance.instance_variable_set(@accessor_key, {})
      end

      # checked(:never) - O(object construction x prop count)
      sig { override.returns(T::Hash[T.untyped, T.untyped]).checked(:never) }
      def default
        {}
      end
    end

    class ApplyDefaultFactory < ApplyDefault
      # checked(:never) - We do this with `T.let` instead
      sig do
        params(
          cls: Module,
          factory: T.any(Proc, Method),
          accessor_key: Symbol,
          setter_proc: SetterFactory::SetterProc,
        )
        .void
        .checked(:never)
      end
      def initialize(cls, factory, accessor_key, setter_proc)
        @class = T.let(cls, Module)
        @factory = T.let(factory, T.any(Proc, Method))
        super(accessor_key, setter_proc)
      end

      # checked(:never) - O(object construction x prop count)
      sig { override.params(instance: T.all(T::Props::Optional, Object)).void.checked(:never) }
      def set_default(instance)
        # Use the actual setter to validate the factory returns a legitimate
        # value every time
        instance.instance_exec(default, &@setter_proc)
      end

      # checked(:never) - O(object construction x prop count)
      sig { override.returns(T.untyped).checked(:never) }
      def default
        @class.class_exec(&@factory)
      end
    end
  end
end
