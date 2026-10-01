# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks for empty strings in conditional stanzas.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # arch arm: "-arm64", intel: ""
      # arch_var = on_arch_conditional arm: "", intel: "-x86_64"
      # os macos: "-darwin", linux: ""
      # os_var = on_system_conditional macos: "", linux: "-gnu"
      #
      # # good
      # arch arm: "-arm64"
      # arch_var = on_arch_conditional intel: "-x86_64"
      # os macos: "-darwin"
      # os_var = on_system_conditional linux: "-gnu"
      # ```
      class EmptyConditionalArgument < Base
        include RangeHelp
        extend AutoCorrector

        MSG_KEY = "Remove the empty `%<key>s:` argument from the `%<stanza>s` stanza."
        MSG_STANZA = "Remove the `%<stanza>s` stanza as all its arguments are empty."

        SYSTEM_STANZAS = [:arch, :os].freeze
        ON_CONDITIONAL_STANZAS = [:on_arch_conditional, :on_system_conditional].freeze
        CONDITIONAL_STANZAS = T.let(
          [*SYSTEM_STANZAS, *ON_CONDITIONAL_STANZAS].freeze,
          T::Array[Symbol],
        )

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          stanza = node.method_name
          return if !CONDITIONAL_STANZAS.include?(stanza) || node.receiver
          return unless (hash = node.first_argument)&.hash_type?

          pairs = hash.pairs
          return if pairs.none? { |pair| empty_string_value?(pair) }

          if SYSTEM_STANZAS.include?(stanza) && pairs.all? { |pair| empty_string_value?(pair) }
            add_offense(node, message: format(MSG_STANZA, stanza:)) do |corrector|
              corrector.remove(range_by_whole_lines(node.source_range, include_final_newline: true))
            end
            return
          elsif ON_CONDITIONAL_STANZAS.include?(stanza) && pairs.all? { |pair| empty_string_value?(pair) }
            if conditional_variable?(node.parent)
              add_offense(node.parent, message: format(MSG_STANZA, stanza:)) do |corrector|
                corrector.remove(range_by_whole_lines(node.parent.source_range, include_final_newline: true))
              end
            else
              add_offense(node, message: format(MSG_STANZA, stanza:)) do |corrector|
                corrector.replace(node.source_range, '""')
              end
            end
            return
          end

          pairs.each_with_index do |pair, index|
            next unless empty_string_value?(pair)

            key = (pair.key.sym_type? || pair.key.str_type?) ? pair.key.value : pair.key.source

            add_offense(pair, message: format(MSG_KEY, stanza:, key:)) do |corrector|
              range = if index.zero?
                pair.source_range.join(pairs.fetch(1).source_range.begin)
              else
                pairs.fetch(index - 1).source_range.end.join(pair.source_range.end)
              end
              corrector.remove(range)
            end
          end
        end

        private

        sig { params(pair: RuboCop::AST::PairNode).returns(T::Boolean) }
        def empty_string_value?(pair)
          pair.value.str_type? && pair.value.value.empty?
        end

        def_node_matcher :conditional_variable?, <<~PATTERN
          (lvasgn _ (send nil? {#{ON_CONDITIONAL_STANZAS.map(&:inspect).join(" ")}} ...))
        PATTERN
      end
    end
  end
end
