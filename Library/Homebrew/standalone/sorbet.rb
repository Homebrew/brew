# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "extend/module"

# Disable runtime checking unless enabled.
# In the future we should consider not doing this monkey patch,
# if assured that there is no performance hit from removing this.
# There are mechanisms to achieve a middle ground (`default_checked_level`).
if ENV["HOMEBREW_SORBET_RUNTIME"]
  T::Configuration.enable_final_checks_on_hooks
  if ENV["HOMEBREW_SORBET_RECURSIVE"] == "1"
    module T
      module Types
        class FixedArray < Base
          def valid?(obj) = recursively_valid?(obj)
        end

        class FixedHash < Base
          def valid?(obj) = recursively_valid?(obj)
        end

        class Intersection < Base
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedArray < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedEnumerable < Base
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedEnumeratorChain < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedEnumeratorLazy < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedHash < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedRange < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class TypedSet < TypedEnumerable
          def valid?(obj) = recursively_valid?(obj)
        end

        class Union < Base
          def valid?(obj) = recursively_valid?(obj)
        end
      end
    end
  end
else
  # Redefine `T.let`, etc. to return the value without dispatching to
  # sorbet-runtime at all: these methods are called often enough (e.g. for
  # every `Pathname` allocation) that even the disabled-check dispatch is
  # measurable.
  # @private
  module TNoChecks
    def cast(value, _type, checked: false)
      value
    end

    def let(value, _type, checked: false)
      value
    end

    def bind(value, _type, checked: false)
      value
    end

    def assert_type!(value, _type, checked: false)
      value
    end
  end

  # Redefine type constructors to return a shared untyped instance: their
  # results are only consumed by runtime checking, which is disabled.
  # @private
  module TNoOpTypeConstructors
    # Not frozen: `Untyped`/`Union` memoise internally on first use.
    # rubocop:disable Style/MutableConstant
    UNTYPED = T::Types::Untyped.new
    # Only `nilable` may return a type containing `NilClass`: `prop`/`const`
    # infer optionality from their type argument, so a nilable prop must still
    # look nilable or serialising it while nil raises. Every other
    # constructor here (including generic container element types like
    # `T::Array[...]`) must stay non-nilable, or props declared with them
    # silently lose their `default:` on deserialization.
    NILABLE_UNTYPED = T::Types::Union.new([T::Types::Untyped.new, T::Types::Simple.new(NilClass)])
    # rubocop:enable Style/MutableConstant

    def nilable(_type) = NILABLE_UNTYPED
    def any(*_types) = UNTYPED
    def all(*_types) = UNTYPED
    def class_of(_klass) = UNTYPED
    def untyped = UNTYPED
    def anything = UNTYPED
    def self_type = UNTYPED
    def attached_class = UNTYPED
    def type_parameter(_name) = UNTYPED
  end

  # @private
  module TNoOpTypeIndex
    def [](*_types) = TNoOpTypeConstructors::UNTYPED
  end

  [T::Array, T::Hash, T::Set, T::Range, T::Enumerable, T::Enumerator].each do |mod|
    mod.singleton_class.prepend(TNoOpTypeIndex)
  end

  # @private
  module T
    class << self
      prepend TNoChecks
      prepend TNoOpTypeConstructors
    end

    # Redefine `T.sig` to be a no-op.
    module Sig
      def sig(arg0 = nil, &blk); end
    end
  end

  # For any cases the above doesn't handle: make sure we don't let TypeError slip through.
  T::Configuration.call_validation_error_handler = ->(signature, opts) {}
  T::Configuration.inline_type_error_handler = ->(error, opts) {}
end
