# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks that the keys of a cask's `arch`/`on_arch_conditional` and
      # `os`/`on_system_conditional` stanza are ordered like the `on_<system>` blocks:
      # ARM before Intel, and macOS before Linux.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # arch intel: "...", arm: "..."
      # arch_var = on_arch_conditional intel: "...", arm: "..."
      # os linux: "...", macos: "..."
      # os_var = on_system_conditional linux: "...", macos: "..."
      #
      # # good
      # arch arm: "...", intel: "..."
      # arch_var = on_arch_conditional arm: "...", intel: "..."
      # os macos: "...", linux: "..."
      # os_var = on_system_conditional macos: "...", linux: "..."
      # ```
      class ConditionalArgumentsOrder < Base
        include RangeHelp
        extend AutoCorrector

        MESSAGE = "`%<stanza>s` keys should be ordered: %<keys>s"

        ARCH_STANZAS = [:arch, :on_arch_conditional].freeze
        OS_STANZAS = [:os, :on_system_conditional].freeze
        ON_CONDITIONAL_STANZAS = [:on_arch_conditional, :on_system_conditional].freeze

        ARCH_ORDER = [:arm, :intel].freeze
        OS_ORDER = [:macos, :linux].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          stanza = node.method_name
          order = case stanza
          when *ARCH_STANZAS then ARCH_ORDER
          when *OS_STANZAS then OS_ORDER
          else return
          end
          return if node.receiver || !(hash = node.first_argument)&.hash_type?

          pairs = hash.pairs
          return unless pairs.all? { |pair| pair.key.sym_type? && order.include?(pair.key.value) }

          sorted = pairs.each_with_index
                        .sort_by { |pair, index| [order.index(pair.key.value), index] }
                        .map(&:first)
          return if pairs == sorted

          node = node.parent if conditional_variable?(node.parent)
          add_offense(node, message: format(MESSAGE, stanza:, keys: order.join(", "))) do |corrector|
            corrector.replace(hash.source_range, rebuild(sorted))
          end
        end

        private

        sig { params(pairs: T::Array[RuboCop::AST::PairNode]).returns(String) }
        def rebuild(pairs)
          pairs.each.map do |pair|
            "#{pair.key.source}: #{pair.value.source}"
          end.join(", ")
        end

        def_node_matcher :conditional_variable?, <<~PATTERN
          (lvasgn _ (send nil? {#{ON_CONDITIONAL_STANZAS.map(&:inspect).join(" ")}} ...))
        PATTERN
      end
    end
  end
end
