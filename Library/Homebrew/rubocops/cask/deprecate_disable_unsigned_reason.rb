# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks for use of `because: :unsigned` in `deprecate!`/`disable!`
      # and replaces it with the preferred `:fails_gatekeeper_check` reason.
      #
      # Example
      #   # bad
      #   deprecate! date: "2024-01-01", because: :unsigned
      #   disable! because: :unsigned
      #
      #   # good
      #   deprecate! date: "2024-01-01", because: :fails_gatekeeper_check
      #   disable! because: :fails_gatekeeper_check
      class DeprecateDisableUnsignedReason < Base
        include CaskHelp
        extend AutoCorrector

        STANZAS_TO_CHECK = [:deprecate!, :disable!].freeze
        MESSAGE = "Use `:fails_gatekeeper_check` instead of `:unsigned` for deprecate!/disable! reason."

        sig { override.params(stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(stanza_block)
          stanzas = stanza_block.stanzas.select { |s| STANZAS_TO_CHECK.include?(s.stanza_name) }
          stanzas.each do |stanza|
            stanza_node = T.cast(stanza.stanza_node, RuboCop::AST::SendNode)
            hash_node = stanza_node.last_argument
            next unless hash_node&.hash_type?

            # find `because: :unsigned` pairs
            T.cast(hash_node, RuboCop::AST::HashNode).each_pair do |key_node, value_node|
              next if !key_node.sym_type? || key_node.value != :because
              next if !value_node.sym_type? || value_node.value != :unsigned

              add_offense(value_node, message: MESSAGE) do |corrector|
                corrector.replace(value_node.source_range, ":fails_gatekeeper_check")
              end
            end
          end
        end
      end
    end
  end
end
