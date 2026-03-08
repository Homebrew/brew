# typed: strict
# frozen_string_literal: true

require "rspec/matchers"

module Tapioca
  module Compilers
    # Generates RBI stubs for custom RSpec matchers defined in test files.
    # Custom matchers are defined via:
    #   - RSpec::Matchers.define :name do |args|
    #   - RSpec::Matchers.define_negated_matcher :new_name, :base
    #   - RSpec::Matchers.alias_matcher :new_name, :old_name
    #   - matcher :name do |args| (inside describe/context/shared_context blocks)
    #   - alias_matcher :new, :old (inside describe/context blocks)
    #   - define_negated_matcher :new, :base (inside describe/context blocks)
    #
    # All custom matchers are added to RSpec::Matchers so Sorbet recognises them in
    # example groups, which include RSpec::Matchers automatically.
    class RSpecCustomMatchers < Tapioca::Dsl::Compiler
      BUILT_IN_MATCHER_METHODS = T.let(
        RSpec::Matchers.instance_methods(false).to_set.freeze,
        T::Set[Symbol],
      )

      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [RSpec::Matchers]

      sig { override.void }
      def decorate
        matchers = collect_custom_matchers
        return if matchers.empty?

        root.create_path(constant) do |mod|
          matchers.each do |name, params, return_type|
            mod.create_method(name, parameters: params, return_type:)
          end
        end
      end

      private

      sig { returns(T::Array[[String, T::Array[RBI::TypedParam], String]]) }
      def collect_custom_matchers
        seen = T.let(Set.new, T::Set[String])
        matchers = T.let([], T::Array[[String, T::Array[RBI::TypedParam], String]])
        test_dir = File.expand_path("../../../test", __dir__)

        Dir.glob("#{test_dir}/**/*.rb").each do |file|
          add_matchers_from_source(File.read(file), seen, matchers)
        end

        matchers
      end

      sig {
        params(
          source:   String,
          seen:     T::Set[String],
          matchers: T::Array[[String, T::Array[RBI::TypedParam], String]],
        ).void
      }
      def add_matchers_from_source(source, seen, matchers)
        scan_define(source, seen, matchers)
        scan_negated(source, seen, matchers)
        scan_alias(source, seen, matchers)
        scan_matcher_dsl(source, seen, matchers)
      end

      # Handles: RSpec::Matchers.define :name do |args|
      sig {
        params(
          source:   String,
          seen:     T::Set[String],
          matchers: T::Array[[String, T::Array[RBI::TypedParam], String]],
        ).void
      }
      def scan_define(source, seen, matchers)
        source.scan(/^\s*RSpec::Matchers\.define\s+:(\w+)(?:[^\n]*do\s*\|([^|]*)\|)?/).each do |captures|
          arr = T.cast(captures, T::Array[T.nilable(String)])
          name = arr[0]
          args_str = arr[1]
          next if name.nil?
          next if seen.include?(name) || BUILT_IN_MATCHER_METHODS.include?(name.to_sym)

          seen.add(name)
          matchers << [name, parse_block_params(args_str), "RSpec::Matchers::DSL::Matcher"]
        end
      end

      # Handles: (RSpec::Matchers.)?define_negated_matcher :new_name, :base
      sig {
        params(
          source:   String,
          seen:     T::Set[String],
          matchers: T::Array[[String, T::Array[RBI::TypedParam], String]],
        ).void
      }
      def scan_negated(source, seen, matchers)
        source.scan(/^\s*(?:RSpec::Matchers\.)?define_negated_matcher\s+:(\w+),\s+:\w+/).each do |captures|
          arr = T.cast(captures, T::Array[T.nilable(String)])
          name = arr[0]
          next if name.nil?
          next if seen.include?(name) || BUILT_IN_MATCHER_METHODS.include?(name.to_sym)

          seen.add(name)
          matchers << [name, optional_expected_param, "RSpec::Matchers::AliasedNegatedMatcher"]
        end
      end

      # Handles: (RSpec::Matchers.)?alias_matcher :new_name, :old_name
      sig {
        params(
          source:   String,
          seen:     T::Set[String],
          matchers: T::Array[[String, T::Array[RBI::TypedParam], String]],
        ).void
      }
      def scan_alias(source, seen, matchers)
        source.scan(/^\s*(?:RSpec::Matchers\.)?alias_matcher\s+:(\w+),\s+:\w+/).each do |captures|
          arr = T.cast(captures, T::Array[T.nilable(String)])
          name = arr[0]
          next if name.nil?
          next if seen.include?(name) || BUILT_IN_MATCHER_METHODS.include?(name.to_sym)

          seen.add(name)
          matchers << [name, optional_expected_param, "RSpec::Matchers::AliasedMatcherWithOperatorSupport"]
        end
      end

      # Handles: matcher :name do |args| (inside describe/context/shared_context with
      # extend RSpec::Matchers::DSL)
      sig {
        params(
          source:   String,
          seen:     T::Set[String],
          matchers: T::Array[[String, T::Array[RBI::TypedParam], String]],
        ).void
      }
      def scan_matcher_dsl(source, seen, matchers)
        source.scan(/^\s+matcher\s+:(\w+)(?:[^\n]*do\s*\|([^|]*)\|)?/).each do |captures|
          arr = T.cast(captures, T::Array[T.nilable(String)])
          name = arr[0]
          args_str = arr[1]
          next if name.nil?
          next if seen.include?(name) || BUILT_IN_MATCHER_METHODS.include?(name.to_sym)

          seen.add(name)
          matchers << [name, parse_block_params(args_str), "RSpec::Matchers::DSL::Matcher"]
        end
      end

      # An optional `expected` parameter matching the signature of built-in matchers like `output`.
      sig { returns(T::Array[RBI::TypedParam]) }
      def optional_expected_param
        [create_opt_param("expected", type: "T.untyped", default: "T.unsafe(nil)")]
      end

      sig { params(args_str: T.nilable(String)).returns(T::Array[RBI::TypedParam]) }
      def parse_block_params(args_str)
        return [] if args_str.nil? || args_str.strip.empty?

        result = T.let([], T::Array[RBI::TypedParam])
        args_str.split(",").each do |arg|
          arg = arg.strip
          next if arg.empty?

          result << if arg.start_with?("**")
            param_name = arg.delete_prefix("**")
            param_name = "kwargs" if param_name.empty?
            create_kw_rest_param(param_name, type: "T.untyped")
          elsif arg.start_with?("*")
            param_name = arg.delete_prefix("*")
            param_name = "args" if param_name.empty?
            create_rest_param(param_name, type: "T.untyped")
          else
            create_param(arg, type: "T.untyped")
          end
        end
        result
      end
    end
  end
end
