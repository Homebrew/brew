# typed: strict
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's stanzas are ordered correctly, including nested within `on_*` blocks.
      # @see https://docs.brew.sh/Cask-Cookbook#stanza-order
      class StanzaOrder < Base
        include IgnoredNode
        extend AutoCorrector
        include CaskHelp

        MESSAGE = "`%<stanza>s` stanza out of order"

        sig { override.params(stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(stanza_block)
          stanzas = stanza_block.stanzas
          ordered_stanzas = sort_stanzas(stanzas)

          return if stanzas == ordered_stanzas

          stanzas.zip(ordered_stanzas).each do |stanza_before, stanza_after|
            next if stanza_before == stanza_after

            add_offense(
              stanza_before.method_node,
              message: format(MESSAGE, stanza: stanza_before.stanza_name),
            ) do |corrector|
              next if part_of_ignored_node?(stanza_before.method_node)
              raise "unexpected nil value for stanza_after" unless stanza_after

              corrector.replace(
                stanza_before.source_range_with_comments,
                stanza_after.source_with_comments,
              )

              # Ignore node so that nested content is not auto-corrected and clobbered.
              ignore_node(stanza_before.method_node)
            end
          end
        end

        sig { override.void }
        def on_new_investigation
          super

          ignored_nodes.clear
        end

        private

        sig { params(stanzas: T::Array[RuboCop::Cask::AST::Stanza]).returns(T::Array[RuboCop::Cask::AST::Stanza]) }
        def sort_stanzas(stanzas)
          sort_depends_on_stanzas = stanzas.all? do |stanza|
            stanza.stanza_name != :depends_on || !depends_on_sort_key(stanza).nil?
          end
          stanzas.each_with_index.sort_by do |stanza, index|
            [
              stanza.stanza_index || raise("unexpected nil stanza index"),
              if sort_depends_on_stanzas && stanza.stanza_name == :depends_on
                depends_on_sort_key(stanza)
              else
                ""
              end,
              index,
            ]
          end.map(&:first)
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).returns(T.nilable(String)) }
        def depends_on_sort_key(stanza)
          node = stanza.stanza_node
          return unless node.is_a?(RuboCop::AST::SendNode)

          argument = node.first_argument
          return unless argument
          return argument.value.to_s.downcase if argument.sym_type?
          return unless argument.hash_type?

          return unless argument.pairs.all? do |pair|
            next false unless pair.key.sym_type?

            values = pair.value.array_type? ? pair.value.values : [pair.value]
            values.all? { |value| value.sym_type? || value.str_type? }
          end

          sort_key = []
          argument.pairs.each do |pair|
            sort_key << pair.key.value.to_s.downcase
            values = pair.value.array_type? ? pair.value.values : [pair.value]
            values.each do |value|
              sort_key << value.value.to_s.downcase
            end
          end
          sort_key.join("\0")
        end
      end
    end
  end
end
