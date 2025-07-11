# frozen_string_literal: true
# typed: ignore

# Work around an interaction bug with sorbet-runtime and rspec-mocks,
# which occurs when using message expectations (*_any_instance_of,
# expect, allow) and and_call_original.
#
# When a sig is defined, sorbet-runtime will replace the sigged method
# with a wrapper that, upon first invocation, re-wraps the method with a faster
# implementation.
#
# When expect_any_instance_of is used, rspec stores a reference to the first wrapper,
# to be restored later.
#
# The first wrapper is invoked as part of the test and sorbet-runtime replaces
# the method definition with the second wrapper.
#
# But when mocks are cleaned up, rspec restores back to the first wrapper.
# Upon subsequent invocations, the first wrapper is called, and sorbet-runtime
# throws a runtime error, since this is an unexpected state.
#
# We work around this by forcing re-wrapping before rspec stores a reference
# to the method.
if defined? ::RSpec::Mocks
  module T
    module CompatibilityPatches
      module RSpecCompatibility
        module RecorderExtensions
          def observe!(method_name)
            if @klass.method_defined?(method_name.to_sym)
              method = @klass.instance_method(method_name.to_sym)
              T::Private::Methods.maybe_run_sig_block_for_method(method)
            end
            super(method_name)
          end
        end
        ::RSpec::Mocks::AnyInstance::Recorder.prepend(RecorderExtensions) if defined?(::RSpec::Mocks::AnyInstance::Recorder)

        module MethodDoubleExtensions
          def initialize(object, method_name, proxy)
            if ::Kernel.instance_method(:respond_to?).bind(object).call(method_name, true) # rubocop:disable Performance/BindCall
              method = ::RSpec::Support.method_handle_for(object, method_name)
              T::Private::Methods.maybe_run_sig_block_for_method(method)
            end
            super(object, method_name, proxy)
          end
        end
        ::RSpec::Mocks::MethodDouble.prepend(MethodDoubleExtensions) if defined?(::RSpec::Mocks::MethodDouble)
      end
    end
  end
end

# Work around for sorbet-runtime wrapped methods.
#
# When a sig is defined, sorbet-runtime will replace the sigged method
# with a wrapper. Those wrapper methods look like `foo(*args, &blk)`
# so that wrappers can handle and pass on all the arguments supplied.
#
# However, that creates a problem with runtime reflection on the methods,
# since when a sigged method is introspected, it will always return its
# `arity` as `-1`, its `parameters` as `[[:rest, :args], [:block, :blk]]`,
# and its `source_location` as `[<some_file_in_sorbet>, <some_line_number>]`.
#
# This might be a problem for some applications that rely on getting the
# correct information from these methods.
#
# This compatibility module, when prepended to the `Method` class, would fix
# the return values of `arity`, `parameters` and `source_location`.
#
# @example
#   require 'sorbet-runtime'
#   ::Method.prepend(T::CompatibilityPatches::MethodExtensions)
module T
  module CompatibilityPatches
    module MethodExtensions
      def arity
        arity = super
        return arity if arity != -1 || self.is_a?(Proc)
        sig = T::Private::Methods.signature_for_method(self)
        sig ? sig.method.arity : arity
      end

      def source_location
        sig = T::Private::Methods.signature_for_method(self)
        sig ? sig.method.source_location : super
      end

      def parameters
        sig = T::Private::Methods.signature_for_method(self)
        sig ? sig.method.parameters : super
      end
    end
  end
end
