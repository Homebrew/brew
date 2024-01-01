# typed: true
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's stanzas are ordered correctly, including nested within `on_*` blocks.
      # @see https://docs.brew.sh/Cask-Cookbook#stanza-order
      class StanzaOrder < Base
        include IgnoredNode
        extend Forwardable
        extend AutoCorrector
        include CaskHelp

        MESSAGE = "`%<stanza>s` stanza out of order"

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

              corrector.replace(
                stanza_before.source_range_with_comments,
                stanza_after.source_with_comments,
              )

              # Ignore node so that nested content is not auto-corrected and clobbered.
              ignore_node(stanza_before.method_node)
            end
          end
        end

        def on_new_investigation
          super

          ignored_nodes.clear
        end

        private

        def sort_stanzas(stanzas)
          stanzas.sort do |stanza1, stanza2|
            i1 = stanza1.stanza_index
            i2 = stanza2.stanza_index

            if i1 == i2
              i1 = stanzas.index(stanza1)
              i2 = stanzas.index(stanza2)
            end

            i1 - i2
          end
        end

        def stanza_order_index(stanza)
          stanza_name = stanza.respond_to?(:method_name) ? stanza.method_name : stanza.stanza_name
          RuboCop::Cask::Constants::STANZA_ORDER.index(stanza_name)
        end
      end
    end
  end
end
