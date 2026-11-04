# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks Go build arguments inside staged resources.
      class StdGoArgs < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          find_every_method_call_by_name(formula_nodes.body_node, :std_go_args).each do |method|
            next if method.receiver && !method.receiver.self_type?
            next unless (arguments = method.last_argument).is_a?(RuboCop::AST::HashNode)
            next unless arguments.pairs.any? do |pair|
              node_equals?(pair.key, :ldflags) && node_equals?(pair.value, :goreleaser)
            end
            next unless method.each_ancestor(:block).any? do |block|
              block.method_name == :stage &&
              block.send_node.receiver &&
              !block.send_node.receiver.self_type?
            end

            add_offense(method, message: "Do not use `ldflags: :goreleaser` in staged resources; " \
                                         "it uses the formula's metadata.")
          end
        end
      end
    end
  end
end
