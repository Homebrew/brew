# typed: strict

module RuboCop
  module Cop
    module Cask
      class NoAutobump < Base
        sig {
          params(
            base_node: RuboCop::AST::Node,
            block:     T.proc.params(node: RuboCop::AST::SendNode).void,
          ).void
        }
        def reason(base_node, &block); end
      end
    end
  end
end
