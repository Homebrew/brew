# typed: true
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's stanzas are grouped correctly, including nested within `on_*` blocks.
      # @see https://docs.brew.sh/Cask-Cookbook#stanza-order
      class StanzaGrouping < Base
        extend Forwardable
        extend AutoCorrector
        include CaskHelp
        include RangeHelp

        MISSING_LINE_MSG = "stanza groups should be separated by a single empty line"
        EXTRA_LINE_MSG = "stanzas within the same group should have no lines between them"

        def on_cask(cask_block)
          @cask_block = cask_block
          @line_ops = {}
          cask_stanzas = cask_block.toplevel_stanzas
          add_offenses(cask_stanzas)

          return if (on_blocks = on_system_methods(cask_stanzas)).none?

          on_blocks.map(&:method_node).select(&:block_type?).each do |on_block|
            stanzas = inner_stanzas(on_block, processed_source.comments)
            add_offenses(stanzas)
          end
        end

        private

        attr_reader :cask_block, :line_ops

        def_delegators :cask_block, :cask_node, :toplevel_stanzas

        def add_offenses(stanzas)
          stanzas.each_cons(2) do |stanza, next_stanza|
            next unless next_stanza

            if missing_line_after?(stanza, next_stanza)
              add_offense_missing_line(stanza)
            elsif extra_line_after?(stanza, next_stanza)
              add_offense_extra_line(stanza)
            end
          end
        end

        def missing_line_after?(stanza, next_stanza)
          !(stanza.same_group?(next_stanza) ||
            empty_line_after?(stanza))
        end

        def extra_line_after?(stanza, next_stanza)
          stanza.same_group?(next_stanza) &&
            empty_line_after?(stanza)
        end

        def empty_line_after?(stanza)
          source_line_after(stanza).empty?
        end

        def source_line_after(stanza)
          processed_source[index_of_line_after(stanza)]
        end

        def index_of_line_after(stanza)
          stanza.source_range.last_line
        end

        def add_offense_missing_line(stanza)
          line_index = index_of_line_after(stanza)
          line_ops[line_index] = :insert
          add_offense(line_index, message: MISSING_LINE_MSG) do |corrector|
            corrector.insert_before(@range, "\n")
          end
        end

        def add_offense_extra_line(stanza)
          line_index = index_of_line_after(stanza)
          line_ops[line_index] = :remove
          add_offense(line_index, message: EXTRA_LINE_MSG) do |corrector|
            corrector.remove(@range)
          end
        end

        def add_offense(line_index, message:)
          line_length = [processed_source[line_index].size, 1].max
          @range = source_range(processed_source.buffer, line_index + 1, 0,
                                line_length)
          super(@range, message:)
        end
      end
    end
  end
end
