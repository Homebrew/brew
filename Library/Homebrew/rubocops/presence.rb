# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks code that can be written more easily using
      # `Object#presence` defined by Active Support.
      #
      # ### Examples
      #
      # ```ruby
      # # bad
      # a.present? ? a : nil
      #
      # # bad
      # !a.present? ? nil : a
      #
      # # bad
      # a.blank? ? nil : a
      #
      # # bad
      # !a.blank? ? a : nil
      #
      # # good
      # a.presence
      # ```
      #
      # ```ruby
      # # bad
      # a.present? ? a : b
      #
      # # bad
      # !a.present? ? b : a
      #
      # # bad
      # a.blank? ? b : a
      #
      # # bad
      # !a.blank? ? a : b
      #
      # # good
      # a.presence || b
      # ```
      class Presence < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Use `%<prefer>s` instead of `%<current>s`."

        def_node_matcher :redundant_receiver_and_other, <<~PATTERN
          {
            (if
              (send $_recv :present?)
              _recv
              $!begin
            )
            (if
              (send $_recv :blank?)
              $!begin
              _recv
            )
          }
        PATTERN

        def_node_matcher :redundant_negative_receiver_and_other, <<~PATTERN
          {
            (if
              (send (send $_recv :present?) :!)
              $!begin
              _recv
            )
            (if
              (send (send $_recv :blank?) :!)
              _recv
              $!begin
            )
          }
        PATTERN

        sig { params(node: RuboCop::AST::IfNode).void }
        def on_if(node)
          return if ignore_if_node?(node)

          redundant_receiver_and_other(node) do |receiver, other|
            return if ignore_other_node?(other) || receiver.nil?

            register_offense(node, receiver, other)
          end

          redundant_negative_receiver_and_other(node) do |receiver, other|
            return if ignore_other_node?(other) || receiver.nil?

            register_offense(node, receiver, other)
          end
        end

        private

        def register_offense(node, receiver, other)
          add_offense(node, message: message(node, receiver, other)) do |corrector|
            corrector.replace(node, replacement(receiver, other, node.left_sibling))
          end
        end

        def ignore_if_node?(node)
          node.elsif?
        end

        def ignore_other_node?(node)
          node && (node.if_type? || node.rescue_type? || node.while_type?)
        end

        def message(node, receiver, other)
          prefer = replacement(receiver, other, node.left_sibling).gsub(/^\s*|\n/, "")
          current = current(node).gsub(/^\s*|\n/, "")
          format(MSG, prefer:, current:)
        end

        def current(node)
          if !node.ternary? && node.source.include?("\n")
            "#{node.loc.keyword.with(end_pos: node.condition.loc.selector.end_pos).source} ... end"
          else
            node.source.gsub(/\n\s*/, " ")
          end
        end

        def replacement(receiver, other, left_sibling)
          or_source = if other&.send_type?
            build_source_for_or_method(other)
          elsif other.nil? || other.nil_type?
            ""
          else
            " || #{other.source}"
          end

          replaced = "#{receiver.source}.presence#{or_source}"
          left_sibling ? "(#{replaced})" : replaced
        end

        def build_source_for_or_method(other)
          if other.parenthesized? || other.method?("[]") || other.arithmetic_operation? || !other.arguments?
            " || #{other.source}"
          else
            method = method_range(other).source
            arguments = other.arguments.map(&:source).join(", ")

            " || #{method}(#{arguments})"
          end
        end

        def method_range(node)
          range_between(node.source_range.begin_pos, node.first_argument.source_range.begin_pos - 1)
        end
      end
    end
  end
end
