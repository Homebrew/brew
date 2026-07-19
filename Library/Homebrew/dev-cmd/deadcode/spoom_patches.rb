# typed: false # rubocop:disable Sorbet/StrictSigil,Sorbet/TrueSigil
# frozen_string_literal: true

# Temporary backport of Spoom deadcode-remover fixes that are merged upstream
# but not yet in a released gem. Loaded into the `spoom deadcode remove`
# subprocess by `brew deadcode` (via `ruby -r`), never into brew itself.
#
#   - Shopify/spoom#980: removal ate a preceding heredoc (blank-line accounting
#     used a node's `location.end_line`, which Prism reports as the heredoc's
#     opening line rather than its closing terminator).
#   - Shopify/spoom#981: a `private_constant`/`public_constant` referencing a
#     removed constant was left behind, raising `NameError` at load time.
#
# Delete this file and its `-r` wiring in `dev-cmd/deadcode.rb` once brew's
# vendored Spoom includes both fixes.
#
# `typed: false` because it prepends into `Spoom::Deadcode::Remover::NodeRemover`,
# a vendored third-party class with no RBI, so Sorbet cannot resolve the host's
# private methods (`delete_lines`, `delete_chars`, `replace_chars`) it calls.

require "spoom"
require "spoom/deadcode/remover"

module Homebrew
  module SpoomDeadcodePatches
    # Shopify/spoom#980: use the real last line a node occupies (its heredoc
    # terminator) instead of `location.end_line` when accounting for blank lines
    # above the node being removed, so a preceding heredoc is not eaten.
    def delete_node_and_comments_and_sigs(context)
      start_line = context.node.location.start_line
      end_line = context.node.location.end_line

      # TODO: remove once Prism location are fixed
      node = context.node
      case node
      when Prism::ConstantWriteNode, Prism::ConstantOperatorWriteNode,
            Prism::ConstantAndWriteNode, Prism::ConstantOrWriteNode,
            Prism::ConstantPathWriteNode, Prism::ConstantPathOperatorWriteNode,
            Prism::ConstantPathAndWriteNode, Prism::ConstantPathOrWriteNode
        value = node.value
        end_line = value.closing_loc&.start_line || value.location.end_line if value.is_a?(Prism::StringNode)
      end

      # Adjust the lines to remove to include sigs attached to the node
      first_node = context.attached_sigs.first || context.node
      start_line = first_node.location.start_line if first_node

      # Adjust the lines to remove to include comments attached to the node
      first_comment = context.attached_comments(first_node).first
      start_line = first_comment.location.start_line if first_comment

      # Adjust the lines to remove to include previous blank lines
      prev_context = Spoom::Deadcode::Remover::NodeContext.new(
        @old_source, @node_context.comments, first_node, context.nesting
      )
      before = prev_context.previous_node

      # There may be an unrelated comment between the current node and the one before
      # if there is, we only want to delete lines up to the last comment found
      if before
        to_node = first_comment || node
        comment = @node_context.comments_between_lines(node_end_line(before), to_node.location.start_line).last
        before = comment if comment
      end

      if before && node_end_line(before) < start_line - 1
        # There is a node before and a blank line
        start_line = node_end_line(before) + 1
      elsif before.nil?
        # There is no node before, check if there is a blank line
        parent_context = context.parent_context
        # With Prism the StatementsNode location starts at the first line of the first node
        parent_context = parent_context.parent_context if parent_context.node.is_a?(Prism::StatementsNode)
        if parent_context.node.location.start_line < start_line - 1
          # There is a blank line before the node
          start_line = parent_context.node.location.start_line + 1
        end
      end

      # Adjust the lines to remove to include following blank lines
      after = context.next_node
      if before.nil? && after && after.location.start_line > end_line + 1
        end_line = after.location.start_line - 1
      elsif after.nil? && context.parent_node.location.end_line > end_line + 1
        end_line = context.parent_node.location.end_line - 1
      end

      delete_lines(start_line, end_line)
    end

    # Prism reports a node ending in a heredoc as ending on the heredoc's opening
    # line rather than its closing terminator. Return the last line the node
    # actually occupies so blank-line accounting does not treat the heredoc body
    # as blank filler and delete it.
    def node_end_line(node)
      end_line = node.location.end_line
      return end_line unless node.is_a?(Prism::Node)

      stack = node.compact_child_nodes
      until stack.empty?
        child = stack.pop
        next unless child

        heredoc_end = heredoc_terminator_line(child)
        end_line = heredoc_end if heredoc_end && heredoc_end > end_line
        stack.concat(child.compact_child_nodes)
      end
      end_line
    end

    # The last line occupied by `node` if it is a heredoc string (its closing
    # terminator), or `nil` otherwise.
    def heredoc_terminator_line(node)
      case node
      when Prism::StringNode, Prism::InterpolatedStringNode,
           Prism::XStringNode, Prism::InterpolatedXStringNode
        opening = node.opening_loc
        return unless opening&.slice&.start_with?("<<")

        # The terminator's location runs to the newline (column 0 of the next
        # line), so use its start line rather than its end line.
        closing = node.closing_loc
        closing ? closing.start_line : node.location.end_line
      end
    end

    # Shopify/spoom#981: when removing a whole constant assignment, also remove
    # the `private_constant`/`public_constant` call that references it, matching
    # the two branches upstream that delete the whole assign.
    def delete_constant_assignment(context)
      const_context = if context.node.is_a?(Prism::ConstantWriteNode)
        context
      elsif context.parent_context.node.is_a?(Prism::ConstantWriteNode)
        context.parent_context
      end
      remove_constant_visibility_call(const_context) if const_context
      super
    end

    # Remove a following `private_constant`/`public_constant` reference to the
    # constant being removed: delete the whole call when the constant is its only
    # argument, or drop just that symbol when the call lists several constants.
    def remove_constant_visibility_call(context)
      node = context.node
      return unless node.is_a?(Prism::ConstantWriteNode)

      name = node.name
      call = context.next_nodes.find { |sibling| constant_visibility_call?(sibling, name) }
      return unless call.is_a?(Prism::CallNode)

      call_context = Spoom::Deadcode::Remover::NodeContext.new(
        @old_source, @node_context.comments, call, context.nesting
      )
      arguments = call.arguments&.arguments
      if arguments && arguments.size > 1
        delete_symbol_argument(call_context, name)
      else
        delete_node_and_comments_and_sigs(call_context)
      end
    end

    # Whether `node` is a bare `private_constant`/`public_constant` call listing `name`.
    def constant_visibility_call?(node, name)
      return false unless node.is_a?(Prism::CallNode)
      return false unless node.receiver.nil?
      return false if node.name != :private_constant && node.name != :public_constant

      arguments = node.arguments&.arguments
      return false unless arguments

      arguments.any? { |argument| argument.is_a?(Prism::SymbolNode) && argument.value == name.to_s }
    end

    # Drop the `:name` symbol from a `private_constant`/`public_constant` call that
    # lists several constants, keeping the call and the other names intact.
    def delete_symbol_argument(context, name)
      arguments = context.node.arguments&.arguments
      return unless arguments

      index = arguments.index { |argument| argument.is_a?(Prism::SymbolNode) && argument.value == name.to_s }
      return unless index

      argument = arguments.fetch(index)
      prev_argument = arguments[index - 1] if index.positive?
      next_argument = arguments[index + 1]

      if prev_argument && next_argument
        replace_chars(prev_argument.location.end_offset, next_argument.location.start_offset, ", ")
      elsif prev_argument
        delete_chars(prev_argument.location.end_offset, argument.location.end_offset)
      elsif next_argument
        delete_chars(argument.location.start_offset, next_argument.location.start_offset)
      end
    end
  end
end

Spoom::Deadcode::Remover::NodeRemover.prepend(Homebrew::SpoomDeadcodePatches)
