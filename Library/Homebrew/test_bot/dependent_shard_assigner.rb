# typed: strict
# frozen_string_literal: true

require "utils/topological_hash"

module Homebrew
  module TestBot
    # Computes deterministic dependent-to-shard assignments for test-bot.
    class DependentShardAssigner
      ComponentNode = T.type_alias do
        {
          members:        T::Array[String],
          representative: String,
          features:       T::Array[String],
          weight:         Integer,
          size:           Integer,
        }
      end
      private_constant :ComponentNode

      EMPTY_FEATURES = T.let([].freeze, T::Array[String])
      private_constant :EMPTY_FEATURES

      sig {
        params(
          shard_count:         Integer,
          dependency_features: T::Hash[String, T::Array[String]],
          dependency_graph:    T::Hash[String, T::Array[String]],
        ).void
      }
      def initialize(shard_count:, dependency_features:, dependency_graph: {})
        raise ArgumentError, "shard_count must be an integer greater than or equal to 1." if shard_count < 1

        @shard_count = shard_count
        @dependency_features = dependency_features
        @dependency_graph = dependency_graph
      end

      sig { params(formulae: T::Array[T.untyped]).returns(T::Hash[String, Integer]) }
      def assignments(formulae)
        shard_features = Array.new(@shard_count) { Set.new }
        shard_loads = Array.new(@shard_count, 0)
        shard_sizes = Array.new(@shard_count, 0)
        max_shard_size = [(formulae.length.to_f / @shard_count).ceil, 1].max

        formula_names = formulae.map { |formula| formula_full_name(formula) }
        sorted_component_nodes(formula_names).each_with_object({}) do |node, assignment_hash|
          features = node.fetch(:features)
          component_size = node.fetch(:size)
          best_shard_index = best_shard_index_for(features, component_size, shard_features, shard_loads, shard_sizes,
                                                  max_shard_size)

          node.fetch(:members).each do |full_name|
            assignment_hash[full_name] = best_shard_index
          end

          shard_features[best_shard_index].merge(features)
          shard_loads[best_shard_index] += node.fetch(:weight)
          shard_sizes[best_shard_index] += component_size
        end
      end

      sig { params(formulae: T::Array[T.untyped], shard_index: Integer).returns(T::Array[T.untyped]) }
      def shard_formulae(formulae, shard_index:)
        if shard_index < 1 || shard_index > @shard_count
          raise ArgumentError,
                "shard_index must be between 1 and shard_count."
        end

        shard_assignments = assignments(formulae)
        formulae.select do |formula|
          shard_assignments.fetch(formula_full_name(formula)) == shard_index - 1
        end
      end

      private

      sig { params(formula_names: T::Array[String]).returns(T::Array[ComponentNode]) }
      def sorted_component_nodes(formula_names)
        max_component_size = [(formula_names.length.to_f / @shard_count).ceil, 1].max
        component_nodes = strongly_connected_components(formula_names).flat_map do |members|
          if members.length <= max_component_size
            [build_component_node(members)]
          else
            # Prefer keeping cycles together, but split oversized SCCs so a single cycle
            # cannot monopolize a shard and starve parallelism.
            split_oversized_component(members).map do |subset_members|
              build_component_node(subset_members)
            end
          end
        end

        component_nodes.sort_by do |component|
          [-component.fetch(:weight), -component.fetch(:features).length,
           component.fetch(:representative)]
        end
      end

      sig { params(members: T::Array[String]).returns(ComponentNode) }
      def build_component_node(members)
        sorted_members = members.sort
        features = sorted_members.flat_map { |member| @dependency_features.fetch(member, EMPTY_FEATURES) }
                                 .uniq
                                 .sort
        weight = sorted_members.sum do |member|
          [@dependency_features.fetch(member, EMPTY_FEATURES).length, 1].max
        end
        representative = T.must(sorted_members.first)
        {
          members:        sorted_members,
          representative:,
          features:,
          weight:,
          size:           sorted_members.length,
        }
      end

      sig { params(members: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def split_oversized_component(members)
        sorted_members = members.sort_by do |member|
          feature_weight = [@dependency_features.fetch(member, EMPTY_FEATURES).length, 1].max
          [-feature_weight, member]
        end

        sorted_members.each_with_object([]) { |member, grouped_members| grouped_members << [member] }
      end

      sig { params(formula_names: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def strongly_connected_components(formula_names)
        adjacency = normalized_adjacency(formula_names)
        Utils::TopologicalHash.strongly_connected_components_from_adjacency(adjacency).map(&:sort)
      end

      sig { params(formula_names: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
      def normalized_adjacency(formula_names)
        target_names = formula_names.uniq.sort
        target_name_set = target_names.to_set

        target_names.to_h do |full_name|
          children = @dependency_graph.fetch(full_name, EMPTY_FEATURES)
                                      .select { |dependency| target_name_set.include?(dependency) }
                                      .uniq
                                      .sort
          [full_name, children]
        end
      end

      sig {
        params(
          features:       T::Array[String],
          component_size: Integer,
          shard_features: T::Array[T::Set[String]],
          shard_loads:    T::Array[Integer],
          shard_sizes:    T::Array[Integer],
          max_shard_size: Integer,
        ).returns(Integer)
      }
      def best_shard_index_for(features, component_size, shard_features, shard_loads, shard_sizes, max_shard_size)
        eligible_indices = shard_features.each_index.select do |shard_index|
          shard_sizes.fetch(shard_index) + component_size <= max_shard_size
        end
        eligible_indices = shard_features.each_index.to_a if eligible_indices.empty?

        T.must(eligible_indices.min_by do |shard_index|
          overlap = features.count { |feature| shard_features.fetch(shard_index).include?(feature) }
          # Prefer locality first, then lower load and lower shard index for ties.
          [-overlap, shard_loads.fetch(shard_index), shard_sizes.fetch(shard_index), shard_index]
        end)
      end

      sig { params(formula_or_name: T.untyped).returns(String) }
      def formula_full_name(formula_or_name)
        if formula_or_name.respond_to?(:full_name)
          formula_or_name.full_name
        else
          Formulary.factory(formula_or_name).full_name
        end
      end
    end
  end
end
