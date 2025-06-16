# typed: strict

module RuboCop
  module Cop
    module Cask
      class OnSystemConditionals < Base
        sig {
          params(
            base_node: Parser::AST::Node,
            block:     T.proc.params(node: Parser::AST::Node, method: Symbol, value: String).void,
          ).void
        }
        def sha256_on_arch_stanzas(base_node, &block); end
      end
    end
  end
end
