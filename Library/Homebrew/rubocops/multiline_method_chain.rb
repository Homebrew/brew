# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Keeps one dotted call per line when a method chain is split.
      #
      # @example
      #   # bad
      #   dependents.keys.to_set
      #             .merge(other)
      #
      #   # good
      #   dependents.keys.to_set.merge(other)
      #   dependents.keys
      #             .to_set
      #             .merge(other)
      class MultilineMethodChain < Base
        extend AutoCorrector

        MSG = "Keep one dotted call per line in a multiline chain."

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if node.single_line? || (node.block_node || node).chained?

          dots = T.let([], T::Array[Parser::Source::Range])
          call = T.let(node, T.nilable(RuboCop::AST::Node))
          while call.is_a?(RuboCop::AST::SendNode)
            dots << call.loc.dot if call.dot? || call.safe_navigation?
            call = call.receiver
            call = call.send_node if call.is_a?(RuboCop::AST::BlockNode)
          end
          dots.reverse!
          continuation = dots.find(&:begins_its_line?)
          return unless continuation

          dots.each_cons(2) do |pair|
            dot = pair.fetch(1)
            next unless dot.same_line?(pair.fetch(0))
            # A newline after a heredoc opener would put the call inside the string.
            next if processed_source.ast.each_node(:any_str).any? do |str|
              str.heredoc? && str.first_line == dot.line && str.source_range.begin_pos < dot.begin_pos
            end

            add_offense(dot) do |corrector|
              corrector.insert_before(dot, "\n#{" " * continuation.column}")
            end
          end
        end
        alias on_csend on_send
      end
    end
  end
end
