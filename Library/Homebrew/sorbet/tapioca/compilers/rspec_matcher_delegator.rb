# typed: strict
# frozen_string_literal: true

require "rspec/matchers"

module Tapioca
  module Compilers
    # Generates RBI stubs for RSpec::Matchers::MatcherDelegator covering the
    # methods it can respond to at runtime via method_missing delegation.
    #
    # MatcherDelegator wraps any matcher and forwards unknown calls to it.
    # Rather than individual manual shims or a blanket T.untyped escape-hatch,
    # this compiler enumerates every public method defined on a concrete
    # RSpec::Matchers::BuiltIn subclass (but not already on BaseMatcher or
    # MatcherDelegator itself) and declares it on MatcherDelegator. The result
    # is that only methods which genuinely exist on some built-in matcher are
    # allowed — e.g. `to_stdout`/`to_stderr` from Output, `by`/`from`/`to`
    # from Change, `with`/`argument` from RespondTo, etc. Calls to methods
    # that exist on no built-in matcher still raise a type error.
    class RSpecMatcherDelegator < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(RSpec::Matchers::MatcherDelegator) } }

      sig { override.returns(T::Enumerable[T.class_of(RSpec::Matchers::MatcherDelegator)]) }
      def self.gather_constants = [RSpec::Matchers::MatcherDelegator]

      sig { override.void }
      def decorate
        methods = delegatable_methods
        return if methods.empty?

        root.create_path(constant) do |klass|
          methods.each do |method_name, params|
            klass.create_method(method_name.to_s, parameters: params, return_type: "T.untyped")
          end
        end
      end

      private

      # Returns a hash of method_name => typed params for every public method
      # that is defined on some RSpec::Matchers::BuiltIn concrete subclass but
      # is absent from BaseMatcher and MatcherDelegator. The first definition
      # encountered (alphabetical by class name) wins for the parameter list.
      sig { returns(T::Hash[Symbol, T::Array[RBI::TypedParam]]) }
      def delegatable_methods
        base_methods      = RSpec::Matchers::BuiltIn::BaseMatcher.public_instance_methods.to_set
        delegator_methods = constant.public_instance_methods.to_set

        result = T.let({}, T::Hash[Symbol, T::Array[RBI::TypedParam]])

        RSpec::Matchers::BuiltIn.constants.sort.each do |const_name|
          obj = T.cast(RSpec::Matchers::BuiltIn.const_get(const_name), T.untyped)
          next if !obj.is_a?(Class) || !(obj < RSpec::Matchers::BuiltIn::BaseMatcher)

          obj.public_instance_methods(false).sort.each do |method_name|
            next if base_methods.include?(method_name)
            next if delegator_methods.include?(method_name)
            next if result.key?(method_name)

            result[method_name] = params_from(T.unsafe(obj).instance_method(method_name))
          end
        end

        result
      end

      sig { params(method: UnboundMethod).returns(T::Array[RBI::TypedParam]) }
      def params_from(method)
        result = T.let([], T::Array[RBI::TypedParam])

        method.parameters.each do |param_info|
          type      = T.cast(param_info[0], Symbol)
          name      = T.cast(param_info[1], T.nilable(Symbol))
          name_str  = (name || :arg).to_s

          typed_param = case type
          when :req    then create_param(name_str, type: "T.untyped")
          when :opt    then create_opt_param(name_str, type: "T.untyped", default: "T.unsafe(nil)")
          when :rest   then create_rest_param(name_str, type: "T.untyped")
          when :keyreq then create_kw_param(name_str, type: "T.untyped")
          when :key    then create_kw_opt_param(name_str, type: "T.untyped", default: "T.unsafe(nil)")
          when :keyrest then create_kw_rest_param(name_str, type: "T.untyped")
          when :block then create_block_param(name_str, type: "T.untyped")
          else next
          end

          result << typed_param
        end

        result
      end
    end
  end
end
