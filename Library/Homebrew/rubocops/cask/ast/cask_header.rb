# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cask
    module AST
      # This class wraps the AST method node that represents the cask header. It
      # includes various helper methods to aid cops in their analysis.
      class CaskHeader
        sig { params(method_node: T.all(RuboCop::AST::Node, RuboCop::AST::ParameterizedNode::RestArguments)).void }
        def initialize(method_node)
          @method_node = method_node
        end

        sig { returns(T.all(RuboCop::AST::Node, RuboCop::AST::ParameterizedNode::RestArguments)) }
        attr_reader :method_node

        sig { returns(String) }
        def header_str
          @header_str ||= T.let(source_range.source, T.nilable(String))
        end

        sig { returns(Parser::Source::Range) }
        def source_range
          @source_range ||= T.let(method_node.loc.expression, T.nilable(Parser::Source::Range))
        end

        sig { returns(String) }
        def preferred_header_str
          "cask '#{cask_token}'"
        end

        sig { returns(String) }
        def cask_token
          @cask_token ||= T.let(method_node.first_argument.str_content, T.nilable(String))
        end

        sig { returns(T.all(RuboCop::AST::Node, RuboCop::AST::ParameterizedNode::RestArguments)) }
        def hash_node
          @hash_node ||= T.let(method_node.each_child_node(:hash).first, T.nilable(RuboCop::AST::Node))
        end

        sig { returns(T.all(RuboCop::AST::Node, RuboCop::AST::ParameterizedNode::RestArguments)) }
        def pair_node
          @pair_node ||= T.let(hash_node.each_child_node(:pair).first, T.nilable(RuboCop::AST::Node))
        end
      end
    end
  end
end
