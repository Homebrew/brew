# typed: strict
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cask
    module AST
      class StanzaBlock
        extend T::Helpers

        sig { returns(RuboCop::AST::BlockNode) }
        attr_reader :block_node

        sig { returns(T::Array[Parser::Source::Comment]) }
        attr_reader :comments

        sig { params(block_node: RuboCop::AST::BlockNode, comments: T::Array[Parser::Source::Comment]).void }
        def initialize(block_node, comments)
          @block_node = block_node
          @comments = comments
        end

        sig { returns(T::Array[Stanza]) }
        def stanzas
          return [] unless (block_body = block_node.block_body)

          # If a block only contains one stanza, it is that stanza's direct parent, otherwise
          # stanzas are grouped in a nested block and the block is that nested block's parent.
          is_stanza = if block_body.begin_block?
            ->(node) { node.parent.parent == block_node }
          else
            ->(node) { node.parent == block_node }
          end

          @stanzas ||= T.let(
            block_body.each_node
                      .select(&:stanza?)
                      .select(&is_stanza)
                      .map { |node| Stanza.new(node, comments) },
            T.nilable(T::Array[Stanza]),
          )
        end
      end

      # This class wraps the AST block node that represents the entire cask
      # definition. It includes various helper methods to aid cops in their
      # analysis.
      class CaskBlock < StanzaBlock
        extend Forwardable

        sig { returns(RuboCop::AST::BlockNode) }
        def cask_node
          block_node
        end

        def_delegator :cask_node, :block_body, :cask_body

        sig { returns(CaskHeader) }
        def header
          @header ||= T.let(CaskHeader.new(block_node.method_node), T.nilable(CaskHeader))
        end

        # TODO: Use `StanzaBlock#stanzas` for all cops, where possible.
        sig { returns(T::Array[Stanza]) }
        def stanzas
          return [] unless cask_body

          @stanzas ||= cask_body.each_node
                                .select(&:stanza?)
                                .map { |node| Stanza.new(node, comments) }
        end

        sig { returns(T::Array[Stanza]) }
        def toplevel_stanzas
          # If a `cask` block only contains one stanza, it is that stanza's direct parent,
          # otherwise stanzas are grouped in a block and `cask` is that block's parent.
          is_toplevel_stanza = if cask_body.begin_block?
            ->(stanza) { stanza.parent_node.parent.cask_block? }
          else
            ->(stanza) { stanza.parent_node.cask_block? }
          end

          @toplevel_stanzas ||= T.let(stanzas.select(&is_toplevel_stanza), T.nilable(T::Array[Stanza]))
        end
      end
    end
  end
end
