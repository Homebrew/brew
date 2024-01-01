# typed: true
# frozen_string_literal: true

module RuboCop
  module AST
    # Extensions for RuboCop's AST Node class.
    class Node
      include RuboCop::Cask::Constants

      def_node_matcher :method_node, "{$(send ...) (block $(send ...) ...)}"
      def_node_matcher :block_args,  "(block _ $_ _)"
      def_node_matcher :block_body,  "(block _ _ $_)"

      def_node_matcher :key_node,    "{(pair $_ _) (hash (pair $_ _) ...)}"
      def_node_matcher :val_node,    "{(pair _ $_) (hash (pair _ $_) ...)}"

      def_node_matcher :cask_block?, "(block (send nil? :cask ...) args ...)"
      def_node_matcher :on_system_block?,
                       "(block (send nil? {#{ON_SYSTEM_METHODS.map(&:inspect).join(" ")}} ...) args ...)"
      def_node_matcher :arch_variable?, "(lvasgn _ (send nil? :on_arch_conditional ...))"

      def_node_matcher :begin_block?, "(begin ...)"

      sig { returns(T::Boolean) }
      def cask_on_system_block?
        (on_system_block? && each_ancestor.any?(&:cask_block?)) || false
      end

      def stanza?
        return true if arch_variable?

        case self
        when RuboCop::AST::BlockNode, RuboCop::AST::SendNode
          ON_SYSTEM_METHODS.include?(method_name) || STANZA_ORDER.include?(method_name)
        else false
        end
      end

      def heredoc?
        loc.is_a?(Parser::Source::Map::Heredoc)
      end

      def location_expression
        base_expression = loc.expression
        descendants.select(&:heredoc?).reduce(base_expression) do |expr, node|
          expr.join(node.loc.heredoc_end)
        end
      end
    end
  end
end
