# typed: strict

module RuboCop
  module Cop
    module Cask
      class ConditionalArgumentsOrder < Base
        sig {
          params(
            base_node: RuboCop::AST::Node,
            block:     T.nilable(T.proc.params(node: RuboCop::AST::SendNode).void),
          ).returns(T::Boolean)
        }
        def conditional_variable?(base_node, &block); end
      end
    end
  end
end
