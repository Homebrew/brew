# frozen_string_literal: true

module Prism
  class ParseResult
    # The :line tracepoint event gets fired whenever the Ruby VM encounters an
    # expression on a new line. The types of expressions that can trigger this
    # event are:
    #
    # * if statements
    # * unless statements
    # * nodes that are children of statements lists
    #
    # In order to keep track of the newlines, we have a list of offsets that
    # come back from the parser. We assign these offsets to the first nodes that
    # we find in the tree that are on those lines.
    #
    # Note that the logic in this file should be kept in sync with the Java
    # MarkNewlinesVisitor, since that visitor is responsible for marking the
    # newlines for JRuby/TruffleRuby.
    class Newlines < Visitor
      # Create a new Newlines visitor with the given newline offsets.
      def initialize(newline_marked)
        @newline_marked = newline_marked
      end

      # Permit block/lambda nodes to mark newlines within themselves.
      def visit_block_node(node)
        old_newline_marked = @newline_marked
        @newline_marked = Array.new(old_newline_marked.size, false)

        begin
          super(node)
        ensure
          @newline_marked = old_newline_marked
        end
      end

      alias_method :visit_lambda_node, :visit_block_node

      # Mark if/unless nodes as newlines.
      def visit_if_node(node)
        node.set_newline_flag(@newline_marked)
        super(node)
      end

      alias_method :visit_unless_node, :visit_if_node

      # Permit statements lists to mark newlines within themselves.
      def visit_statements_node(node)
        node.body.each do |child|
          child.set_newline_flag(@newline_marked)
        end
        super(node)
      end
    end

    private_constant :Newlines

    # Walk the tree and mark nodes that are on a new line.
    def mark_newlines!
      value.accept(Newlines.new(Array.new(1 + source.offsets.size, false)))
    end
  end
end
