# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "ast_constants"
require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks for correct order of components in formulae.
      #
      # - `component_precedence_list` has component hierarchy in a nested list
      #   where each sub array contains components' details which are at same precedence level
      class ComponentsOrder < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          @present_components, @offensive_nodes = check_order(FORMULA_COMPONENT_PRECEDENCE_LIST, body_node)

          component_problem @offensive_nodes[0], @offensive_nodes[1] if @offensive_nodes

          component_precedence_list = [
            [{ name: :depends_on, type: :method_call }],
            [{ name: :resource, type: :block_call }],
            [{ name: :patch, type: :method_call }, { name: :patch, type: :block_call }],
          ]

          head_blocks = find_blocks(body_node, :head)
          head_blocks.each do |head_block|
            check_block_component_order(FORMULA_COMPONENT_PRECEDENCE_LIST, head_block)
          end

          on_system_methods.each do |on_method|
            on_method_blocks = find_blocks(body_node, on_method)
            next if on_method_blocks.empty?

            if on_method_blocks.length > 1
              @offensive_node = on_method_blocks.second
              problem "There can only be one `#{on_method}` block in a formula."
            end

            check_on_system_block_content(component_precedence_list, on_method_blocks.first)
          end

          resource_blocks = find_blocks(body_node, :resource)
          resource_blocks.each do |resource_block|
            check_block_component_order(FORMULA_COMPONENT_PRECEDENCE_LIST, resource_block)

            on_system_blocks = {}

            on_system_methods.each do |on_method|
              on_system_blocks[on_method] = find_blocks(resource_block.body, on_method)
            end

            if on_system_blocks.empty?
              # Found nothing. Try without .body as depending on the code,
              # on_{system} might be in .body or not ...
              on_system_methods.each do |on_method|
                on_system_blocks[on_method] = find_blocks(resource_block, on_method)
              end
            end
            next if on_system_blocks.empty?

            @offensive_node = resource_block

            on_system_bodies = T.let([], T::Array[[RuboCop::AST::BlockNode, RuboCop::AST::Node]])

            on_system_blocks.each_value do |blocks|
              blocks.each do |on_system_block|
                on_system_body = on_system_block.body
                branches = on_system_body.if_type? ? on_system_body.branches : [on_system_body]
                on_system_bodies += branches.map { |branch| [on_system_block, branch] }
              end
            end

            message = T.let(nil, T.nilable(String))
            allowed_methods = [
              [:url, :sha256],
              [:url, :mirror, :sha256],
              [:url, :version, :sha256],
              [:url, :mirror, :version, :sha256],
            ]
            minimum_methods = allowed_methods.first.map { |m| "`#{m}`" }.to_sentence
            maximum_methods = allowed_methods.last.map { |m| "`#{m}`" }.to_sentence

            on_system_bodies.each do |on_system_block, on_system_body|
              method_name = on_system_block.method_name
              child_nodes = on_system_body.begin_type? ? on_system_body.child_nodes : [on_system_body]
              if child_nodes.all? { |n| n.send_type? || n.block_type? || n.lvasgn_type? }
                method_names = child_nodes.filter_map do |node|
                  next if node.lvasgn_type?
                  next if node.method_name == :patch
                  next if on_system_methods.include? node.method_name

                  node.method_name
                end
                next if method_names.empty? || allowed_methods.include?(method_names)
              end
              offending_node(on_system_block)
              message = "`#{method_name}` blocks within `resource` blocks must contain at least " \
                        "#{minimum_methods} and at most #{maximum_methods} (in order)."
              break
            end

            if message
              problem message
              next
            end

            on_system_blocks.each do |on_method, blocks|
              if blocks.length > 1
                problem "There can only be one `#{on_method}` block in a resource block."
                next
              end
            end
          end
        end

        def check_block_component_order(component_precedence_list, block)
          @present_components, offensive_node = check_order(component_precedence_list, block.body)
          component_problem(*offensive_node) if offensive_node
        end

        def check_on_system_block_content(component_precedence_list, on_system_block)
          if on_system_block.body.block_type? && !on_system_methods.include?(on_system_block.body.method_name) &&
             on_system_block.body.method_name != :fails_with
            offending_node(on_system_block)
            problem "Nest `#{on_system_block.method_name}` blocks inside `#{on_system_block.body.method_name}` " \
                    "blocks when there is only one inner block." do |corrector|
              original_source = on_system_block.source.split("\n")
              new_source = [original_source.second, original_source.first, *original_source.drop(2)]
              corrector.replace(on_system_block.source_range, new_source.join("\n"))
            end
          end
          on_system_allowed_methods = %w[
            livecheck
            keg_only
            disable!
            deprecate!
            depends_on
            conflicts_with
            fails_with
            resource
            patch
            pour_bottle?
          ]
          on_system_allowed_methods += on_system_methods.map(&:to_s)
          _, offensive_node = check_order(component_precedence_list, on_system_block.body)
          component_problem(*offensive_node) if offensive_node
          child_nodes = on_system_block.body.begin_type? ? on_system_block.body.child_nodes : [on_system_block.body]
          child_nodes.each do |child|
            valid_node = depends_on_node?(child)
            # Check for RuboCop::AST::SendNode and RuboCop::AST::BlockNode instances
            # only, as we are checking the method_name for `patch`, `resource`, etc.
            method_type = child.send_type? || child.block_type?
            next unless method_type

            valid_node ||= on_system_allowed_methods.include? child.method_name.to_s

            @offensive_node = child
            next if valid_node

            problem "`#{on_system_block.method_name}` cannot include `#{child.method_name}`. " \
                    "Only #{on_system_allowed_methods.map { |m| "`#{m}`" }.to_sentence} are allowed."
          end
        end

        # Reorder two nodes in the source, using the corrector instance in autocorrect method.
        # Components of same type are grouped together when rewriting the source.
        # Linebreaks are introduced if components are of two different methods/blocks/multilines.
        def reorder_components(corrector, node1, node2)
          # order_idx : node1's index in component_precedence_list
          # curr_p_idx: node1's index in preceding_comp_arr
          # preceding_comp_arr: array containing components of same type
          order_idx, curr_p_idx, preceding_comp_arr = get_state(node1)

          # curr_p_idx.positive? means node1 needs to be grouped with its own kind
          if curr_p_idx.positive?
            node2 = preceding_comp_arr[curr_p_idx - 1]
            indentation = " " * (start_column(node2) - line_start_column(node2))
            line_breaks = node2.multiline? ? "\n\n" : "\n"
            corrector.insert_after(node2.source_range, line_breaks + indentation + node1.source)
          else
            indentation = " " * (start_column(node2) - line_start_column(node2))
            # No line breaks up to version_scheme, order_idx == 8
            line_breaks = (order_idx > 8) ? "\n\n" : "\n"
            corrector.insert_before(node2.source_range, node1.source + line_breaks + indentation)
          end
          corrector.remove(range_with_surrounding_space(range: node1.source_range, side: :left))
        end

        # Returns precedence index and component's index to properly reorder and group during autocorrect.
        def get_state(node1)
          @present_components.each_with_index do |comp, idx|
            return [idx, comp.index(node1), comp] if comp.member?(node1)
          end
        end

        def check_order(component_precedence_list, body_node)
          present_components = component_precedence_list.map do |components|
            components.flat_map do |component|
              case component[:type]
              when :method_call
                find_method_calls_by_name(body_node, component[:name]).to_a
              when :block_call
                find_blocks(body_node, component[:name]).to_a
              when :method_definition
                find_method_def(body_node, component[:name])
              end
            end.compact
          end

          # Check if each present_components is above rest of the present_components
          offensive_nodes = T.let(nil, T.nilable(T::Array[RuboCop::AST::Node]))
          present_components.take(present_components.size - 1).each_with_index do |preceding_component, p_idx|
            next if preceding_component.empty?

            present_components.drop(p_idx + 1).each do |succeeding_component|
              next if succeeding_component.empty?

              offensive_nodes = check_precedence(preceding_component, succeeding_component)
              return [present_components, offensive_nodes] if offensive_nodes
            end
          end
          nil
        end

        # Method to report and correct component precedence violations.
        def component_problem(component1, component2)
          return if tap_style_exception? :components_order_exceptions

          problem "`#{format_component(component1)}` (line #{line_number(component1)}) " \
                  "should be put before `#{format_component(component2)}` " \
                  "(line #{line_number(component2)})" do |corrector|
            reorder_components(corrector, component1, component2)
          end
        end

        # Node pattern method to match
        # `depends_on` variants.
        def_node_matcher :depends_on_node?, <<~EOS
          {(if _ (send nil? :depends_on ...) nil?)
           (send nil? :depends_on ...)}
        EOS
      end
    end
  end
end
