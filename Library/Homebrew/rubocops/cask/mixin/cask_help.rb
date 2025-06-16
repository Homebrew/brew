# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # Common functionality for cops checking casks.
      module CaskHelp
        prepend CommentsHelp # Update the rbi file if changing this: https://github.com/sorbet/sorbet/issues/259

        sig { overridable.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block); end

        sig { overridable.params(cask_stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(cask_stanza_block); end

        sig { params(block_node: RuboCop::AST::BlockNode).void }
        def on_block(block_node)
          super if defined? super

          return if !block_node.cask_block? && !block_node.cask_on_system_block?

          comments = comments_in_range(block_node).to_a
          stanza_block = RuboCop::Cask::AST::StanzaBlock.new(block_node, comments)
          on_cask_stanza_block(stanza_block)

          return unless block_node.cask_block?

          @file_path = T.let(processed_source.file_path, T.nilable(String))

          cask_block = RuboCop::Cask::AST::CaskBlock.new(block_node, comments)
          on_cask(cask_block)
        end

        sig {
          params(
            cask_stanzas: T::Array[RuboCop::Cask::AST::Stanza],
          ).returns(
            T::Array[RuboCop::Cask::AST::Stanza],
          )
        }
        def on_system_methods(cask_stanzas)
          cask_stanzas.select(&:on_system_block?)
        end

        sig {
          params(
            block_node: RuboCop::AST::BlockNode,
            comments:   T::Array[String],
          ).returns(
            T::Array[RuboCop::Cask::AST::Stanza],
          )
        }
        def inner_stanzas(block_node, comments)
          block_contents = block_node.child_nodes.select(&:begin_type?)
          inner_nodes = block_contents.map(&:child_nodes).flatten.select(&:send_type?)
          inner_nodes.map { |n| RuboCop::Cask::AST::Stanza.new(n, comments) }
        end

        sig { returns(T.nilable(String)) }
        def cask_tap
          return unless (match_obj = @file_path&.match(%r{/(homebrew-\w+)/}))

          match_obj[1]
        end
      end
    end
  end
end
