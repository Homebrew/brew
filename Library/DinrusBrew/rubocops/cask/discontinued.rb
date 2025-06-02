# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop corrects `caveats { discontinued }` to `deprecate!`.
      class Discontinued < Base
        include CaskHelp
        extend AutoCorrector

        MESSAGE = "Use `deprecate!` instead of `caveats { discontinued }`."

        sig { override.params(stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(stanza_block)
          stanza_block.stanzas.select(&:caveats?).each do |stanza|
            find_discontinued_method_call(stanza.stanza_node) do |node|
              if caveats_contains_only_discontinued?(node.parent)
                add_offense(node.parent, message: MESSAGE) do |corrector|
                  corrector.replace(node.parent.source_range,
                                    "deprecate! date: \"#{Date.today}\", because: :discontinued")
                end
              else
                add_offense(node, message: MESSAGE)
              end
            end
          end
        end

        def_node_matcher :caveats_contains_only_discontinued?, <<~EOS
          (block
            (send nil? :caveats)
            (args)
            (send nil? :discontinued))
        EOS

        def_node_search :find_discontinued_method_call, <<~EOS
          $(send nil? :discontinued)
        EOS
      end
    end
  end
end
