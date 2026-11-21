# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Keep branching, operators and multi-step computations out of inline expressions.
      # Allow up to three calls and argument values, including inside deferred blocks.
      # A nested call counts towards the limit once, even when passed as an argument.
      # Parentheses and freezing a value do not add to the count.
      module SimpleExpression
        extend NodePattern::Macros

        MAX_VALUE_PARTS = 3

        def_node_matcher :literal_or_reference?, <<~PATTERN
          {
            basic_literal? variable? reference? self zsuper
            (block_pass {nil? #value_operand?})
            (any_block {(send nil? {:lambda :proc}) (lambda) (send (const {nil? cbase} {:Hash :Proc}) :new)}
                       {(args {arg restarg kwarg kwrestarg blockarg shadowarg}*) !args} {nil? #simple_value?})
            (const {nil? cbase #simple_value?} _)
            ({array hash pair splat kwsplat dstr dsym regexp} #simple_value?*)
            ({irange erange} {nil? #simple_value?} {nil? #simple_value?})
          }
        PATTERN

        def_node_matcher :integer_literal?, "{int (begin #integer_literal?)}"

        # Literal calculations also express sizes, bit masks and paths relative to constants.
        def_node_matcher :static_expression?, <<~PATTERN
          {basic_literal? (const {nil? cbase #static_expression?} _) (begin #static_expression?)
           (send #integer_literal? :<< #static_expression?)
           (send [!nil? #static_expression?] {:+ :- :* :/ :** :>> :| :&} #static_expression?)}
        PATTERN

        private

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def excessive_logic?(node)
          !simple_value?(node) || value_parts(node) > MAX_VALUE_PARTS
        end

        sig { params(node: RuboCop::AST::Node).returns(Integer) }
        def value_parts(node)
          case node
          when RuboCop::AST::SendNode
            receiver = node.receiver
            return value_parts(receiver) if receiver && node.method?(:freeze) && !node.arguments?
            # Ruby parses an unbound bare name as an implicit call.
            return 0 if !receiver && !node.arguments? && !node.parenthesized?

            return 1 + (receiver ? value_parts(receiver) : 0) + node.arguments.sum { |arg| [1, value_parts(arg)].max }
          when RuboCop::AST::BlockNode
            body = node.body
            return 1 + node.argument_list.size + (body ? value_parts(body) : 0)
          when RuboCop::AST::HashNode
            return node.child_nodes.sum { |pair| [1, value_parts(pair)].max } unless node.braces?
          end
          node.child_nodes.sum { |child| value_parts(child) }
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def value_operand?(node) = simple_value?(node, operand: true)

        sig { params(node: RuboCop::AST::Node, operand: T::Boolean).returns(T::Boolean) }
        def simple_value?(node, operand: false)
          if node.begin_type?
            children = node.child_nodes
            return false unless children.one?

            return simple_value?(children.fetch(0), operand:)
          end
          return !literal_or_reference?(node).nil? unless node.is_a?(RuboCop::AST::SendNode)
          return false if node.assignment_method?

          receiver = node.receiver
          if receiver && !node.arguments?
            return simple_value?(receiver, operand:) if node.method?(:freeze)
            return value_operand?(receiver) if [:+@, :-@].include?(node.method_name)
          end

          if node.method?(:[])
            return false unless node.arguments?
          elsif node.operator_method?
            return !static_expression?(node).nil?
          elsif operand && node.arguments? && ![:dig, :fetch].include?(node.method_name)
            return false
          end

          (!receiver || value_operand?(receiver)) && node.arguments.all? { |arg| value_operand?(arg) }
        end
      end
    end
  end
end
