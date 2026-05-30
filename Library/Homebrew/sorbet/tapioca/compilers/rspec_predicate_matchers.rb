# typed: strict
# frozen_string_literal: true

require "rspec/expectations"

module Tapioca
  module Compilers
    class RspecPredicateMatchers < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants
        [::RSpec::Matchers]
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |mod|
          missing_predicate_matchers.each do |name|
            mod.create_method(
              name,
              parameters: [
                create_rest_param("args", type: "T.untyped"),
                create_block_param("block", type: "T.untyped"),
              ],
            )
          end
        end
      end

      private

      sig { returns(T::Array[String]) }
      def missing_predicate_matchers
        (used_predicate_matchers - known_rspec_predicate_matchers).to_a.sort
      end

      sig { returns(T::Set[String]) }
      def used_predicate_matchers
        matchers = T.let(Set.new, T::Set[String])

        Dir[File.join(__dir__, "../../../test/**/*_spec.rb")].each do |file|
          File.read(file).scan(/\b(?:be|have)_[a-z0-9_]+\b/) do |name|
            matchers.add(name)
          end
        end

        matchers
      end

      sig { returns(T::Set[String]) }
      def known_rspec_predicate_matchers
        known = T.let(Set.new, T::Set[String])

        Dir[File.join(__dir__, "../../rbi/gems/rspec-expectations@*.rbi")].each do |file|
          File.read(file).scan(/^\s*def\s+((?:be|have)_[a-z0-9_!?]+)/) do |name|
            known.add(name.first)
          end
        end

        known
      end
    end
  end
end
