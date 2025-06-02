# typed: strict

module RuboCop
  module Cop
    module Cask
      class Discontinued < Base
        sig {
          params(
            base_node: RuboCop::AST::Node,
            block:     T.nilable(T.proc.params(node: RuboCop::AST::SendNode).void),
          ).returns(T::Boolean)
        }
        def caveats_contains_only_discontinued?(base_node, &block); end

        sig {
          params(
            base_node: RuboCop::AST::Node,
            block:     T.proc.params(node: RuboCop::AST::SendNode).void,
          ).void
        }
        def find_discontinued_method_call(base_node, &block); end
      end
    end
  end
end
