# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks for correct order of `depends_on` in formulae.
      #
      # precedence order:
      # build-time > test > normal > recommended > optional
      class DependencyOrder < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node

          check_dependency_nodes_order(body_node)
          check_uses_from_macos_nodes_order(body_node)
          ([:head, :stable] + on_system_methods).each do |block_name|
            block = find_block(body_node, block_name)
            next unless block

            check_dependency_nodes_order(block.body)
            check_uses_from_macos_nodes_order(block.body)
          end
        end

        def check_uses_from_macos_nodes_order(parent_node)
          return if parent_node.nil?

          dependency_nodes = parent_node.each_child_node.select { |x| uses_from_macos_node?(x) }
          ensure_dependency_order(dependency_nodes)
        end

        def check_dependency_nodes_order(parent_node)
          return if parent_node.nil?

          dependency_nodes = parent_node.each_child_node.select { |x| depends_on_node?(x) }
          ensure_dependency_order(dependency_nodes)
        end

        def ensure_dependency_order(nodes)
          ordered = nodes.sort_by { |node| dependency_name(node).downcase }
          ordered = sort_dependencies_by_type(ordered)
          sort_conditional_dependencies!(ordered)
          verify_order_in_source(ordered)
        end

        # Separate dependencies according to precedence order:
        # build-time > test > normal > recommended > optional
        def sort_dependencies_by_type(dependency_nodes)
          unsorted_deps = dependency_nodes.to_a
          ordered = []
          ordered.concat(unsorted_deps.select { |dep| buildtime_dependency? dep })
          unsorted_deps -= ordered
          ordered.concat(unsorted_deps.select { |dep| test_dependency? dep })
          unsorted_deps -= ordered
          ordered.concat(unsorted_deps.reject { |dep| negate_normal_dependency? dep })
          unsorted_deps -= ordered
          ordered.concat(unsorted_deps.select { |dep| recommended_dependency? dep })
          unsorted_deps -= ordered
          ordered.concat(unsorted_deps.select { |dep| optional_dependency? dep })
        end

        # `depends_on :apple if build.with? "foo"` should always be defined
        #  after `depends_on :foo`.
        # This method reorders the dependencies array according to the above rule.
        sig { params(ordered: T::Array[RuboCop::AST::Node]).returns(T::Array[RuboCop::AST::Node]) }
        def sort_conditional_dependencies!(ordered)
          length = ordered.size
          idx = 0
          while idx < length
            idx1 = T.let(nil, T.nilable(Integer))
            idx2 = T.let(nil, T.nilable(Integer))
            ordered.each_with_index do |dep, pos|
              idx = pos+1
              match_nodes = build_with_dependency_name(dep)
              next if match_nodes.blank?

              idx1 = pos
              ordered.drop(idx1+1).each_with_index do |dep2, pos2|
                next unless match_nodes.index(dependency_name(dep2))

                idx2 = pos2 if idx2.nil? || pos2 > idx2
              end
              break if idx2
            end
            insert_after!(ordered, idx1, idx2 + T.must(idx1)) if idx2
          end
          ordered
        end

        # Verify actual order of sorted `depends_on` nodes in source code;
        # raise RuboCop problem otherwise.
        def verify_order_in_source(ordered)
          ordered.each_with_index do |node_1, idx|
            l1 = line_number(node_1)
            l2 = T.let(nil, T.nilable(Integer))
            node_2 = T.let(nil, T.nilable(RuboCop::AST::Node))
            ordered.drop(idx + 1).each do |test_node|
              l2 = line_number(test_node)
              node_2 = test_node if l2 < l1
            end
            next unless node_2

            offending_node(node_1)

            problem "`dependency \"#{dependency_name(node_1)}\"` (line #{l1}) should be put before " \
                    "`dependency \"#{dependency_name(node_2)}\"` (line #{l2})" do |corrector|
              indentation = " " * (start_column(node_2) - line_start_column(node_2))
              line_breaks = "\n"
              corrector.insert_before(node_2.source_range,
                                      node_1.source + line_breaks + indentation)
              corrector.remove(range_with_surrounding_space(range: node_1.source_range, side: :left))
            end
          end
        end

        # Node pattern method to match
        # `depends_on` variants.
        def_node_matcher :depends_on_node?, <<~EOS
          {(if _ (send nil? :depends_on ...) nil?)
           (send nil? :depends_on ...)}
        EOS

        def_node_matcher :uses_from_macos_node?, <<~EOS
          {(if _ (send nil? :uses_from_macos ...) nil?)
           (send nil? :uses_from_macos ...)}
        EOS

        def_node_search :buildtime_dependency?, "(sym :build)"

        def_node_search :recommended_dependency?, "(sym :recommended)"

        def_node_search :test_dependency?, "(sym :test)"

        def_node_search :optional_dependency?, "(sym :optional)"

        def_node_search :negate_normal_dependency?, "(sym {:build :recommended :test :optional})"

        # Node pattern method to extract `name` in `depends_on :name` or `uses_from_macos :name`
        def_node_search :dependency_name_node, <<~EOS
          {(send nil? {:depends_on :uses_from_macos} {(hash (pair $_ _) ...) $({str sym} _) $(const nil? _)} ...)
           (if _ (send nil? :depends_on {(hash (pair $_ _)) $({str sym} _) $(const nil? _)}) nil?)}
        EOS

        # Node pattern method to extract `name` in `build.with? :name`
        def_node_search :build_with_dependency_node, <<~EOS
          (send (send nil? :build) :with? $({str sym} _))
        EOS

        def insert_after!(arr, idx1, idx2)
          arr.insert(idx2+1, arr.delete_at(idx1))
        end

        def build_with_dependency_name(node)
          match_nodes = build_with_dependency_node(node)
          match_nodes = match_nodes.to_a.compact
          match_nodes.map { |n| string_content(n) } unless match_nodes.empty?
        end

        def dependency_name(dependency_node)
          match_node = dependency_name_node(dependency_node).to_a.first
          string_content(match_node) if match_node
        end
      end
    end
  end
end
