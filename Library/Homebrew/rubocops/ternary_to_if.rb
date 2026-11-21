# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Prefers modifier `if` or `unless` when initialising a local variable with a nil branch.
      # Existing locals are excluded because skipping assignment would retain their values.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # source = reuse_platforms ? @sources[key] : nil
      # source = skip_platforms ? nil : @sources[key]
      #
      # # good
      # source = @sources[key] if reuse_platforms
      # source = @sources[key] unless skip_platforms
      # ```
      class TernaryToIf < Base
        extend AutoCorrector

        MSG = "Use modifier `%<keyword>s` instead of a ternary with a `nil` fallback."

        sig { returns(T.class_of(VariableForce)) }
        def self.joining_forces
          VariableForce
        end

        sig { params(variable: VariableForce::Variable, _variable_table: VariableForce::VariableTable).void }
        def before_declaring_variable(variable, _variable_table)
          node = variable.declaration_node
          return unless node.is_a?(RuboCop::AST::AsgnNode)
          return unless node.lvasgn_type?
          return unless node.single_line?

          ternary = node.expression
          return unless ternary.is_a?(RuboCop::AST::IfNode)
          return unless ternary.ternary?

          keyword = if ternary.else_branch&.nil_type?
            "if"
          elsif ternary.if_branch&.nil_type?
            "unless"
          end
          return unless keyword
          # Keep generated conditions compatible with Style/UnlessLogicalOperators.
          return if keyword == "unless" && ternary.condition.each_node(:and, :or).any?
          return if ternary.each_descendant(:lvasgn, :match_var, :match_with_lvasgn).any?

          # Loops and retry can reach this declaration with an existing value.
          return if node.each_ancestor(:while, :until, :while_post, :until_post, :for, :rescue).any?
          return if node.each_ancestor(:block, :numblock, :itblock).any? do |block|
            block.each_descendant(:redo).any?
          end

          parent = node.parent
          if parent
            return if parent.is_a?(RuboCop::AST::DefNode) && parent.endless?
            return unless parent.type?(:begin, :kwbegin, :def, :defs, :block, :numblock, :itblock)
          end

          add_offense(node, message: format(MSG, keyword:)) do |corrector|
            branch = if keyword == "if"
              ternary.if_branch
            else
              ternary.else_branch
            end
            corrector.replace(ternary, branch.source)
            corrector.insert_after(node, " #{keyword} #{ternary.condition.source}")
          end
        end
      end
    end
  end
end
