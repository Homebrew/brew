# frozen_string_literal: true
# typed: strict

module T::Props
  module Private
    module SetterFactory
      extend T::Sig

      SetterProc = T.type_alias { T.proc.params(val: T.untyped).void }
      ValueValidationProc = T.type_alias { T.proc.params(val: T.untyped).void }
      ValidateProc = T.type_alias { T.proc.params(prop: Symbol, value: T.untyped).void }

      sig do
        params(
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
          prop: Symbol,
          rules: T::Hash[Symbol, T.untyped]
        )
        .returns([SetterProc, ValueValidationProc])
        .checked(:never)
      end
      def self.build_setter_proc(klass, prop, rules)
        # Our nil check works differently than a simple T.nilable for various
        # reasons (including the `raise_on_nil_write` setting and the existence
        # of defaults & factories), so unwrap any T.nilable and do a check
        # manually.
        non_nil_type = T::Utils::Nilable.get_underlying_type_object(rules.fetch(:type_object))
        accessor_key = rules.fetch(:accessor_key)
        validate = rules[:setter_validate]

        # It seems like a bug that this affects the behavior of setters, but
        # some existing code relies on this behavior
        has_explicit_nil_default = rules.key?(:default) && rules.fetch(:default).nil?

        # Use separate methods in order to ensure that we only close over necessary
        # variables
        if !T::Props::Utils.need_nil_write_check?(rules) || has_explicit_nil_default
          if validate.nil? && non_nil_type.is_a?(T::Types::Simple)
            simple_nilable_proc(prop, accessor_key, non_nil_type.raw_type, klass)
          else
            nilable_proc(prop, accessor_key, non_nil_type, klass, validate)
          end
        else
          if validate.nil? && non_nil_type.is_a?(T::Types::Simple)
            simple_non_nil_proc(prop, accessor_key, non_nil_type.raw_type, klass)
          else
            non_nil_proc(prop, accessor_key, non_nil_type, klass, validate)
          end
        end
      end

      sig do
        params(
          prop: Symbol,
          accessor_key: Symbol,
          non_nil_type: T::Module[T.anything],
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
        )
        .returns([SetterProc, ValueValidationProc])
      end
      private_class_method def self.simple_non_nil_proc(prop, accessor_key, non_nil_type, klass)
        [
          proc do |val|
            unless val.is_a?(non_nil_type)
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                T::Utils.coerce(non_nil_type),
                val,
              )
            end
            instance_variable_set(accessor_key, val)
          end,
          proc do |val|
            unless val.is_a?(non_nil_type)
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                T::Utils.coerce(non_nil_type),
                val,
              )
            end
          end,
        ]
      end

      sig do
        params(
          prop: Symbol,
          accessor_key: Symbol,
          non_nil_type: T::Types::Base,
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
          validate: T.nilable(ValidateProc)
        )
        .returns([SetterProc, ValueValidationProc])
      end
      private_class_method def self.non_nil_proc(prop, accessor_key, non_nil_type, klass, validate)
        [
          proc do |val|
            # this use of recursively_valid? is intentional: unlike for
            # methods, we want to make sure data at the 'edge'
            # (e.g. models that go into databases or structs serialized
            # from disk) are correct, so we use more thorough runtime
            # checks there
            if non_nil_type.recursively_valid?(val)
              validate&.call(prop, val)
            else
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                non_nil_type,
                val,
              )
            end
            instance_variable_set(accessor_key, val)
          end,
          proc do |val|
            # this use of recursively_valid? is intentional: unlike for
            # methods, we want to make sure data at the 'edge'
            # (e.g. models that go into databases or structs serialized
            # from disk) are correct, so we use more thorough runtime
            # checks there
            if non_nil_type.recursively_valid?(val)
              validate&.call(prop, val)
            else
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                non_nil_type,
                val,
              )
            end
          end,
        ]
      end

      sig do
        params(
          prop: Symbol,
          accessor_key: Symbol,
          non_nil_type: T::Module[T.anything],
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
        )
        .returns([SetterProc, ValueValidationProc])
      end
      private_class_method def self.simple_nilable_proc(prop, accessor_key, non_nil_type, klass)
        [
          proc do |val|
            unless val.nil? || val.is_a?(non_nil_type)
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                T::Utils.coerce(non_nil_type),
                val,
              )
            end
            instance_variable_set(accessor_key, val)
          end,
          proc do |val|
            unless val.nil? || val.is_a?(non_nil_type)
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                T::Utils.coerce(non_nil_type),
                val,
              )
            end
          end,
        ]
      end

      sig do
        params(
          prop: Symbol,
          accessor_key: Symbol,
          non_nil_type: T::Types::Base,
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
          validate: T.nilable(ValidateProc),
        )
        .returns([SetterProc, ValueValidationProc])
      end
      private_class_method def self.nilable_proc(prop, accessor_key, non_nil_type, klass, validate)
        [
          proc do |val|
            if val.nil?
              instance_variable_set(accessor_key, nil)
            # this use of recursively_valid? is intentional: unlike for
            # methods, we want to make sure data at the 'edge'
            # (e.g. models that go into databases or structs serialized
            # from disk) are correct, so we use more thorough runtime
            # checks there
            elsif non_nil_type.recursively_valid?(val)
              validate&.call(prop, val)
              instance_variable_set(accessor_key, val)
            else
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                non_nil_type,
                val,
              )
              instance_variable_set(accessor_key, val)
            end
          end,
          proc do |val|
            if val.nil?
            # this use of recursively_valid? is intentional: unlike for
            # methods, we want to make sure data at the 'edge'
            # (e.g. models that go into databases or structs serialized
            # from disk) are correct, so we use more thorough runtime
            # checks there
            elsif non_nil_type.recursively_valid?(val)
              validate&.call(prop, val)
            else
              T::Props::Private::SetterFactory.raise_pretty_error(
                klass,
                prop,
                non_nil_type,
                val,
              )
            end
          end,
        ]
      end

      sig do
        params(
          klass: T.all(T::Module[T.anything], T::Props::ClassMethods),
          prop: Symbol,
          type: T.any(T::Types::Base, T::Module[T.anything]),
          val: T.untyped,
        )
        .void
      end
      def self.raise_pretty_error(klass, prop, type, val)
        base_message = "Can't set #{klass.name}.#{prop} to #{val.inspect} (instance of #{val.class}) - need a #{type}"

        pretty_message = "Parameter '#{prop}': #{base_message}\n"
        caller_loc = caller_locations.find { |l| !l.to_s.include?('sorbet-runtime/lib/types/props') }
        if caller_loc
          pretty_message += "Caller: #{caller_loc.path}:#{caller_loc.lineno}\n"
        end

        T::Configuration.call_validation_error_handler(
          nil,
          message: base_message,
          pretty_message: pretty_message,
          kind: 'Parameter',
          name: prop,
          type: type,
          value: val,
          location: caller_loc,
        )
      end
    end
  end
end
