# typed: strict
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

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          @cask_block = T.let(cask_block, T.nilable(RuboCop::Cask::AST::CaskBlock))
          @line_ops = T.let({}, T.nilable(T::Hash[Integer, Symbol]))
          cask_stanzas = cask_block.toplevel_stanzas
          add_offenses(cask_stanzas)

          return if (on_blocks = on_system_methods(cask_stanzas)).none?

          on_blocks.map(&:method_node).select(&:block_type?).each do |on_block|
            stanzas = inner_stanzas(T.cast(on_block, RuboCop::AST::BlockNode), processed_source.comments)
            add_offenses(stanzas)
          end
        end

        private

        sig { returns(T.nilable(RuboCop::Cask::AST::CaskBlock)) }
        attr_reader :cask_block

        def_delegators :cask_block, :cask_node, :toplevel_stanzas

        sig { params(stanzas: T::Array[RuboCop::Cask::AST::Stanza]).void }
        def add_offenses(stanzas)
          stanzas.each_cons(2) do |stanza, next_stanza|
            next if !stanza || !next_stanza

            if missing_line_after?(stanza, next_stanza)
              add_offense_missing_line(stanza)
            elsif extra_line_after?(stanza, next_stanza)
              add_offense_extra_line(stanza)
            end
          end
        end

        sig { returns(T::Hash[Integer, Symbol]) }
        def line_ops
          @line_ops || raise("Call to line_ops before it has been initialized")
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza, next_stanza: RuboCop::Cask::AST::Stanza).returns(T::Boolean) }
        def missing_line_after?(stanza, next_stanza)
          !(stanza.same_group?(next_stanza) ||
            empty_line_after?(stanza))
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza, next_stanza: RuboCop::Cask::AST::Stanza).returns(T::Boolean) }
        def extra_line_after?(stanza, next_stanza)
          stanza.same_group?(next_stanza) &&
            empty_line_after?(stanza)
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).returns(T::Boolean) }
        def empty_line_after?(stanza)
          source_line_after(stanza).empty?
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).returns(String) }
        def source_line_after(stanza)
          processed_source[index_of_line_after(stanza)]
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).returns(Integer) }
        def index_of_line_after(stanza)
          stanza.source_range.last_line
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).void }
        def add_offense_missing_line(stanza)
          line_index = index_of_line_after(stanza)
          line_ops[line_index] = :insert
          add_offense(line_index, message: MISSING_LINE_MSG) do |corrector|
            corrector.insert_before(@range, "\n")
          end
        end

        sig { params(stanza: RuboCop::Cask::AST::Stanza).void }
        def add_offense_extra_line(stanza)
          line_index = index_of_line_after(stanza)
          line_ops[line_index] = :remove
          add_offense(line_index, message: EXTRA_LINE_MSG) do |corrector|
            corrector.remove(@range)
          end
        end

        sig { params(line_index: Integer, message: String, block: T.proc.params(corrector: RuboCop::Cop::Corrector).void).void }
        def add_offense(line_index, message:, &block)
          line_length = [processed_source[line_index].size, 1].max
          @range = T.let(
            source_range(processed_source.buffer, line_index + 1, 0, line_length),
            T.nilable(Parser::Source::Range),
          )
          super(@range, message:, &block)
        end
      end
    end
  end
end
