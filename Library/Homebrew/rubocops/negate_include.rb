# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Enforces the use of `collection.exclude?(obj)`
      # over `!collection.include?(obj)`.
      #
      # NOTE: This cop is unsafe because false positives will occur for
      #       receiver objects that do not have an `#exclude?` method (e.g. `IPAddr`).
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # !array.include?(2)
      # !hash.include?(:key)
      #
      # # good
      # array.exclude?(2)
      # hash.exclude?(:key)
      # ```
      class NegateInclude < Base
        extend AutoCorrector

        MSG = "Use `.exclude?` and remove the negation part."

        RESTRICT_ON_SEND = [:!].freeze

        def_node_matcher :negate_include_call?, <<~PATTERN
          (send (send $!nil? :include? $_) :!)
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return unless (receiver, obj = negate_include_call?(node))

          add_offense(node) do |corrector|
            corrector.replace(node, "#{receiver.source}.exclude?(#{obj.source})")
          end
        end
      end
    end
  end
end
