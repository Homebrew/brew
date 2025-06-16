# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks if collection can be blank-compacted with `compact_blank`.
      #
      # NOTE: It is unsafe by default because false positives may occur in the
      #       blank check of block arguments to the receiver object.
      #
      #       For example, `[[1, 2], [3, nil]].reject { |first, second| second.blank? }` and
      #       `[[1, 2], [3, nil]].compact_blank` are not compatible. The same is true for `blank?`.
      #       This will work fine when the receiver is a hash object.
      #
      #       And `compact_blank!` has different implementations for `Array`, `Hash` and
      #       `ActionController::Parameters`.
      #       `Array#compact_blank!`, `Hash#compact_blank!` are equivalent to `delete_if(&:blank?)`.
      #       `ActionController::Parameters#compact_blank!` is equivalent to `reject!(&:blank?)`.
      #       If the cop makes a mistake, autocorrected code may get unexpected behavior.
      #
      # ### Examples
      #
      # ```ruby
      # # bad
      # collection.reject(&:blank?)
      # collection.reject { |_k, v| v.blank? }
      #
      # # good
      # collection.compact_blank
      # ```
      #
      # ```ruby
      # # bad
      # collection.delete_if(&:blank?)           # Same behavior as `Array#compact_blank!` and `Hash#compact_blank!`
      # collection.delete_if { |_, v| v.blank? } # Same behavior as `Array#compact_blank!` and `Hash#compact_blank!`
      # collection.reject!(&:blank?)             # Same behavior as `ActionController::Parameters#compact_blank!`
      # collection.reject! { |_k, v| v.blank? }  # Same behavior as `ActionController::Parameters#compact_blank!`
      #
      # # good
      # collection.compact_blank!
      # ```
      class CompactBlank < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Use `%<preferred_method>s` instead."

        RESTRICT_ON_SEND = [:reject, :delete_if, :reject!].freeze

        def_node_matcher :reject_with_block?, <<~PATTERN
          (block
            (send _ {:reject :delete_if :reject!})
            $(args ...)
            (send
              $(lvar _) :blank?))
        PATTERN

        def_node_matcher :reject_with_block_pass?, <<~PATTERN
          (send _ {:reject :delete_if :reject!}
            (block_pass
              (sym :blank?)))
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return unless bad_method?(node)

          range = offense_range(node)
          preferred_method = preferred_method(node)
          add_offense(range, message: format(MSG, preferred_method:)) do |corrector|
            corrector.replace(range, preferred_method)
          end
        end

        private

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def bad_method?(node)
          return true if reject_with_block_pass?(node)

          if (arguments, receiver_in_block = reject_with_block?(node.parent))
            return use_single_value_block_argument?(arguments, receiver_in_block) ||
                   use_hash_value_block_argument?(arguments, receiver_in_block)
          end

          false
        end

        def use_single_value_block_argument?(arguments, receiver_in_block)
          arguments.length == 1 && arguments[0].source == receiver_in_block.source
        end

        def use_hash_value_block_argument?(arguments, receiver_in_block)
          arguments.length == 2 && arguments[1].source == receiver_in_block.source
        end

        sig { params(node: RuboCop::AST::SendNode).returns(Parser::Source::Range) }
        def offense_range(node)
          end_pos = if node.parent&.block_type? && node.parent&.send_node == node
            node.parent.source_range.end_pos
          else
            node.source_range.end_pos
          end

          range_between(node.loc.selector.begin_pos, end_pos)
        end

        sig { params(node: RuboCop::AST::SendNode).returns(String) }
        def preferred_method(node)
          node.method?(:reject) ? "compact_blank" : "compact_blank!"
        end
      end
    end
  end
end
