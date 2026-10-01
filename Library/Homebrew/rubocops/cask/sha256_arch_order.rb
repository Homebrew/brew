# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks that the architecture keys of a cask's `sha256` stanza are ordered
      # like the tags of a formula's `bottle` block: macOS before Linux, ARM before Intel.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # sha256 x86_64_linux: "...",
      #        arm:          "..."
      #
      # # good
      # sha256 arm:          "...",
      #        x86_64_linux: "..."
      # ```
      class Sha256ArchOrder < Base
        extend AutoCorrector
        include CaskHelp

        ARCH_ORDER = RuboCop::Cask::Constants::SHA256_ARCH_ORDER

        MESSAGE = "`sha256` architecture keys should be ordered: arm, intel (or x86_64), arm64_linux, x86_64_linux"

        STANZA_PREFIX = "sha256 "

        sig { override.params(cask_stanza_block: RuboCop::Cask::AST::StanzaBlock).void }
        def on_cask_stanza_block(cask_stanza_block)
          cask_stanza_block.stanzas.each do |stanza|
            node = stanza.stanza_node
            next if stanza.stanza_name != :sha256 || !node.is_a?(RuboCop::AST::SendNode)

            hash_node = node.last_argument
            next if hash_node.nil? || !hash_node.hash_type?

            pairs = hash_node.pairs
            next unless pairs.all? { |pair| pair.key.sym_type? && ARCH_ORDER.include?(pair.key.value) }

            sorted = pairs.each_with_index
                          .sort_by { |pair, index| [ARCH_ORDER.index(pair.key.value), index] }
                          .map(&:first)
            next if pairs == sorted

            add_offense(node, message: MESSAGE) do |corrector|
              next if comments_in_range(node).any?

              corrector.replace(node.source_range, rebuild(node, sorted))
            end
          end
        end

        private

        sig { params(node: RuboCop::AST::SendNode, pairs: T::Array[RuboCop::AST::PairNode]).returns(String) }
        def rebuild(node, pairs)
          width = pairs.map { |pair| pair.key.source.length }.max.to_i
          indent = " " * (node.loc.column + STANZA_PREFIX.length)
          pairs.each_with_index.map do |pair, index|
            key = "#{pair.key.source}:".ljust(width + 2)
            "#{index.zero? ? STANZA_PREFIX : indent}#{key}#{pair.value.source}"
          end.join(",\n")
        end
      end
    end
  end
end
