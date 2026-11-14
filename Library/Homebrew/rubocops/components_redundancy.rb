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

          url_with_revision_and_sha256(body_node) do |url, specs, sha256|
            using_git = if (using = using_spec(specs))
              using.sym_type? && using.value == :git
            else
              string_content(url).match?(%r{^git://|\.git$})
            end

            offending_node(sha256)
            problem "Do not use both `sha256` and `revision:`." do |corrector|
              corrector.remove(range_with_surrounding_space(range: sha256.source_range, side: :left)) if using_git
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

        def_node_search :url_with_revision_and_sha256, <<~PATTERN
          (begin <(send nil? :url $_ $(hash <(pair (sym :revision) _) ...>)) $(send nil? :sha256 ...) ...>)
        PATTERN

        def_node_matcher :using_spec, <<~PATTERN
          (hash <(pair (sym :using) $_) ...>)
        PATTERN
      end
    end
  end
end
