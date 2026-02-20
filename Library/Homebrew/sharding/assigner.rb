# typed: strict
# frozen_string_literal: true

require "utils/topological_hash"

module Homebrew
  module Sharding
    class Assigner
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
          shard_count:      Integer,
          features_by_item: T::Hash[String, T::Array[String]],
          adjacency_graph:  T::Hash[String, T::Array[String]],
        ).void
      }
      def initialize(shard_count:, features_by_item:, adjacency_graph: {})
        raise ArgumentError, "shard_count must be an integer greater than or equal to 1." if shard_count < 1

        @shard_count = shard_count
        @features_by_item = features_by_item
        @adjacency_graph = adjacency_graph
      end

      sig { params(item_ids: T::Array[String]).returns(T::Hash[String, Integer]) }
      def assignments(item_ids)
        canonical_item_ids = canonicalized_item_ids(item_ids)
        shard_features = Array.new(@shard_count) { Set.new }
        shard_loads = Array.new(@shard_count, 0)
        shard_sizes = Array.new(@shard_count, 0)
        max_shard_size = [(canonical_item_ids.length.to_f / @shard_count).ceil, 1].max

        sorted_nodes = sorted_component_nodes(canonical_item_ids)
        target_shard_load = sorted_nodes.sum { |node| node.fetch(:weight) }.to_f / @shard_count

        sorted_nodes.each_with_object({}) do |node, assignment_hash|
          features = node.fetch(:features)
          component_size = node.fetch(:size)
          component_weight = node.fetch(:weight)
          best_shard_index = best_shard_index_for(features, component_size, component_weight, shard_features,
                                                  shard_loads, shard_sizes, max_shard_size, target_shard_load)

          node.fetch(:members).each do |item_id|
            assignment_hash[item_id] = best_shard_index
          end

          shard_features[best_shard_index].merge(features)
          shard_loads[best_shard_index] += component_weight
          shard_sizes[best_shard_index] += component_size
        end
      end

      sig { params(item_ids: T::Array[String], shard_index: Integer).returns(T::Array[String]) }
      def shard_item_ids(item_ids, shard_index:)
        if shard_index < 1 || shard_index > @shard_count
          raise ArgumentError,
                "shard_index must be between 1 and shard_count."
        end

        canonical_item_ids = canonicalized_item_ids(item_ids)
        shard_assignments = assignments(canonical_item_ids)
        canonical_item_ids.select do |item_id|
          shard_assignments.fetch(item_id) == shard_index - 1
        end
      end

      private

      sig { params(item_ids: T::Array[String]).returns(T::Array[String]) }
      def canonicalized_item_ids(item_ids)
        item_ids.uniq.sort
      end

      sig { params(item_ids: T::Array[String]).returns(T::Array[ComponentNode]) }
      def sorted_component_nodes(item_ids)
        max_component_size = [(item_ids.length.to_f / @shard_count).ceil, 1].max
        component_nodes = strongly_connected_components(item_ids).flat_map do |members|
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
        features = sorted_members.flat_map { |member| @features_by_item.fetch(member, EMPTY_FEATURES) }
                                 .uniq
                                 .sort
        weight = sorted_members.sum do |member|
          [@features_by_item.fetch(member, EMPTY_FEATURES).length, 1].max
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
          feature_weight = [@features_by_item.fetch(member, EMPTY_FEATURES).length, 1].max
          [-feature_weight, member]
        end

        sorted_members.each_with_object([]) { |member, grouped_members| grouped_members << [member] }
      end

      sig { params(item_ids: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def strongly_connected_components(item_ids)
        adjacency = normalized_adjacency(item_ids)
        Utils::TopologicalHash.strongly_connected_components_from_adjacency(adjacency).map(&:sort)
      end

      sig { params(item_ids: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
      def normalized_adjacency(item_ids)
        target_ids = canonicalized_item_ids(item_ids)
        target_id_set = target_ids.to_set

        target_ids.to_h do |item_id|
          children = @adjacency_graph.fetch(item_id, EMPTY_FEATURES)
                                     .select { |dependency| target_id_set.include?(dependency) }
                                     .uniq
                                     .sort
          [item_id, children]
        end
      end

      sig {
        params(
          features:          T::Array[String],
          component_size:    Integer,
          component_weight:  Integer,
          shard_features:    T::Array[T::Set[String]],
          shard_loads:       T::Array[Integer],
          shard_sizes:       T::Array[Integer],
          max_shard_size:    Integer,
          target_shard_load: Float,
        ).returns(Integer)
      }
      def best_shard_index_for(features, component_size, component_weight, shard_features, shard_loads, shard_sizes,
                               max_shard_size, target_shard_load)
        eligible_indices = shard_features.each_index.select do |shard_index|
          shard_sizes.fetch(shard_index) + component_size <= max_shard_size
        end
        eligible_indices = shard_features.each_index.to_a if eligible_indices.empty?

        under_target_indices = eligible_indices.select do |shard_index|
          shard_loads.fetch(shard_index) + component_weight <= target_shard_load
        end
        candidate_indices = under_target_indices.presence || eligible_indices
        prioritize_locality = under_target_indices.present?
        overlap_by_shard_index = candidate_indices.to_h do |shard_index|
          overlap = overlap_count(features, shard_features.fetch(shard_index))
          [shard_index, overlap]
        end

        sorted_candidate_indices = candidate_indices.sort_by do |shard_index|
          overlap = overlap_by_shard_index.fetch(shard_index)
          projected_load = shard_loads.fetch(shard_index) + component_weight

          if prioritize_locality
            locality_score_tuple(
              overlap,
              projected_load,
              shard_sizes.fetch(shard_index),
              shard_index,
            )
          else
            load_balance_score_tuple(
              overlap,
              projected_load,
              shard_sizes.fetch(shard_index),
              shard_index,
            )
          end
        end

        sorted_candidate_indices.fetch(0)
      end

      sig { params(features: T::Array[String], shard_feature_set: T::Set[String]).returns(Integer) }
      def overlap_count(features, shard_feature_set)
        features.count { |feature| shard_feature_set.include?(feature) }
      end

      sig { params(overlap: Integer, projected_load: Integer, shard_size: Integer, shard_index: Integer).returns(T::Array[Integer]) }
      def locality_score_tuple(overlap, projected_load, shard_size, shard_index)
        # Keep shared dependency neighborhoods together while the shard
        # remains under target load to reduce duplicate installs.
        [-overlap, projected_load, shard_size, shard_index]
      end

      sig { params(overlap: Integer, projected_load: Integer, shard_size: Integer, shard_index: Integer).returns(T::Array[Integer]) }
      def load_balance_score_tuple(overlap, projected_load, shard_size, shard_index)
        # Once all shards are above target load, prioritize runtime
        # balancing to avoid a long-tail shard dominating wall-clock CI.
        [projected_load, -overlap, shard_size, shard_index]
      end
    end
  end
end
