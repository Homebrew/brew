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
  # Redefine `T.let`, etc. to make the `checked` parameter default to `false` rather than `true`.
  # @private
  module TNoChecks
    def cast(value, type, checked: false)
      super
    end

    def let(value, type, checked: false)
      super
    end

    def bind(value, type, checked: false)
      super
    end

    def assert_type!(value, type, checked: false)
      super
    end
  end

  # @private
  module T
    class << self
      prepend TNoChecks
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
