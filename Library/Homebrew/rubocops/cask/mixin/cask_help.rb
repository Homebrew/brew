# typed: true
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # Common functionality for cops checking casks.
      module CaskHelp
        prepend CommentsHelp

        sig { overridable.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block); end

        sig { overridable.params(cask_stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(cask_stanza_block); end

        # FIXME: Workaround until https://github.com/rubocop/rubocop/pull/11858 is released.
        def find_end_line(node)
          return node.loc.end.line if node.block_type? || node.numblock_type?

          super
        end

        sig { params(block_node: RuboCop::AST::BlockNode).void }
        def on_block(block_node)
          super if defined? super

          return if !block_node.cask_block? && !block_node.cask_on_system_block?

          comments = comments_in_range(block_node).to_a
          stanza_block = RuboCop::Cask::AST::StanzaBlock.new(block_node, comments)
          on_cask_stanza_block(stanza_block)

          return unless block_node.cask_block?

          cask_block = RuboCop::Cask::AST::CaskBlock.new(block_node, comments)
          on_cask(cask_block)
        end

        def on_system_methods(cask_stanzas)
          cask_stanzas.select(&:on_system_block?)
        end

        def inner_stanzas(block_node, comments)
          block_contents = block_node.child_nodes.select(&:begin_type?)
          inner_nodes = block_contents.map(&:child_nodes).flatten.select(&:send_type?)
          inner_nodes.map { |n| RuboCop::Cask::AST::Stanza.new(n, comments) }
        end
      end
    end
  end
end
