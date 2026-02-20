# typed: strict
# frozen_string_literal: true

require "sharding/assigner"

module Homebrew
  module TestBot
    # Dependent-specific adapter over the generic test-bot shard assigner.
    class DependentShardAssigner < Sharding::Assigner
      sig {
        params(
          shard_count:         Integer,
          dependency_features: T::Hash[String, T::Array[String]],
          dependency_graph:    T::Hash[String, T::Array[String]],
        ).void
      }
      def initialize(shard_count:, dependency_features:, dependency_graph: {})
        super(
          shard_count:,
          features_by_item: dependency_features,
          adjacency_graph:  dependency_graph,
        )
      end

      sig { params(formulae: T::Array[T.untyped]).returns(T::Hash[String, Integer]) }
      def assignments(formulae)
        formula_names = formulae.map { |formula| formula_full_name(formula) }
        super(formula_names)
      end

      sig { params(formulae: T::Array[T.untyped], shard_index: Integer).returns(T::Array[T.untyped]) }
      def shard_formulae(formulae, shard_index:)
        formula_names = formulae.map { |formula| formula_full_name(formula) }
        shard_formula_names = shard_item_ids(formula_names, shard_index:).to_set
        seen_formula_names = T.let(Set.new, T::Set[String])

        formulae.select do |formula|
          full_name = formula_full_name(formula)
          shard_formula_names.include?(full_name) && seen_formula_names.add?(full_name)
        end
      end

      private

      sig { params(formula_or_name: T.untyped).returns(String) }
      def formula_full_name(formula_or_name)
        if formula_or_name.respond_to?(:full_name)
          formula_or_name.full_name
        elsif formula_or_name.is_a?(String) && formula_or_name.include?("/")
          formula_or_name
        else
          Formulary.factory(formula_or_name).full_name
        end
      end
    end
  end
end
