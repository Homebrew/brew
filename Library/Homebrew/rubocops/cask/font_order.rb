# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks that a font cask's `font` stanzas are ordered alphabetically.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # font "Foo-Regular.ttf"
      # font "Foo-Bold.ttf"
      #
      # # good
      # font "Foo-Bold.ttf"
      # font "Foo-Regular.ttf"
      # ```
      class FontOrder < Base
        extend AutoCorrector
        include CaskHelp

        MESSAGE = "`font` stanzas should be ordered alphabetically"

        sig { override.params(cask_stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(cask_stanza_block)
          stanzas = cask_stanza_block.stanzas.select(&:font?)
          sorted_stanzas = stanzas.sort_by(&:source)

          stanzas.each_with_index do |stanza, index|
            sorted_stanza = sorted_stanzas.fetch(index)
            next if stanza == sorted_stanza

            add_offense(stanza.method_node, message: MESSAGE) do |corrector|
              corrector.replace(stanza.source_range_with_comments, sorted_stanza.source_with_comments)
            end
          end
        end
      end
    end
  end
end
