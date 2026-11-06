# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks if redundant components are present and for other component errors.
      #
      # - `url|checksum|mirror|version` should be inside `stable` block
      # - `head` and `head do` should not be simultaneously present
      # - `stable do` should not be present without a `head` spec
      # - `stable do` should not be present with only `url|checksum|mirror|version`
      # - `head do` should not be present with only `url`
      class ComponentsRedundancy < FormulaCop
        extend AutoCorrector

        HEAD_MSG = "`head` and `head do` should not be simultaneously present"
        STABLE_MSG = "`stable do` should not be present without a `head` spec"
        STABLE_BLOCK_METHODS = [:url, :sha256, :mirror, :version].freeze

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          find_every_method_call_by_name(body_node, :url).each do |url|
            next if url.arguments.none? do |arg|
              arg.is_a?(RuboCop::AST::HashNode) && arg.keys.each.map(&:value).include?(:revision)
            end

            git_url = string_content(parameters(url).fetch(0)).end_with?(".git")

            find_method_calls_by_name(url.parent, :sha256).each do |sha256|
              offending_node(sha256)
              problem "Do not use both `sha256` and `revision:`." do |corrector|
                corrector.remove(range_with_surrounding_space(range: sha256.source_range, side: :left)) if git_url
              end
            end
          end

          stable_block = find_block(body_node, :stable)
          if stable_block
            STABLE_BLOCK_METHODS.each do |method_name|
              problem "`#{method_name}` should be put inside `stable` block" if method_called?(body_node, method_name)
            end

            unless stable_block.body.nil?
              child_nodes = stable_block.body.begin_type? ? stable_block.body.child_nodes : [stable_block.body]
              if child_nodes.all? { |n| n.send_type? && STABLE_BLOCK_METHODS.include?(n.method_name) }
                problem "`stable do` should not be present with only #{STABLE_BLOCK_METHODS.join("/")}"
              end
            end
          end

          head_block = find_block(body_node, :head)
          if head_block && !head_block.body.nil?
            child_nodes = head_block.body.begin_type? ? head_block.body.child_nodes : [head_block.body]
            shorthand_head_methods = [:url]
            if child_nodes.all? { |n| n.send_type? && shorthand_head_methods.include?(n.method_name) }
              problem "`head do` should not be present with only #{shorthand_head_methods.join("/")}"
            end
          end

          problem HEAD_MSG if method_called?(body_node, :head) &&
                              find_block(body_node, :head)

          return if method_called?(body_node, :head) ||
                    find_block(body_node, :head)

          problem STABLE_MSG if stable_block
        end
      end
    end
  end
end
