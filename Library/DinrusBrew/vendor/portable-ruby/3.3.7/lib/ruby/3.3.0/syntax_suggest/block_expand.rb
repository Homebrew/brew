# frozen_string_literal: true

module SyntaxSuggest
  # This class is responsible for taking a code block that exists
  # at a far indentaion and then iteratively increasing the block
  # so that it captures everything within the same indentation block.
  #
  #   def dog
  #     puts "bow"
  #     puts "wow"
  #   end
  #
  # block = BlockExpand.new(code_lines: code_lines)
  #   .call(CodeBlock.new(lines: code_lines[1]))
  #
  # puts block.to_s
  # # => puts "bow"
  #      puts "wow"
  #
  #
  # Once a code block has captured everything at a given indentation level
  # then it will expand to capture surrounding indentation.
  #
  # block = BlockExpand.new(code_lines: code_lines)
  #   .call(block)
  #
  # block.to_s
  # # => def dog
  #        puts "bow"
  #        puts "wow"
  #      end
  #
  class BlockExpand
    def initialize(code_lines:)
      @code_lines = code_lines
    end

    # Main interface. Expand current indentation, before
    # expanding to a lower indentation
    def call(block)
      if (next_block = expand_neighbors(block))
        next_block
      else
        expand_indent(block)
      end
    end

    # Expands code to the next lowest indentation
    #
    # For example:
    #
    #   1 def dog
    #   2   print "dog"
    #   3 end
    #
    # If a block starts on line 2 then it has captured all it's "neighbors" (code at
    # the same indentation or higher). To continue expanding, this block must capture
    # lines one and three which are at a different indentation level.
    #
    # This method allows fully expanded blocks to decrease their indentation level (so
    # they can expand to capture more code up and down). It does this conservatively
    # as there's no undo (currently).
    def expand_indent(block)
      now = AroundBlockScan.new(code_lines: @code_lines, block: block)
        .force_add_hidden
        .stop_after_kw
        .scan_adjacent_indent

      now.lookahead_balance_one_line

      now.code_block
    end

    # A neighbor is code that is at or above the current indent line.
    #
    # First we build a block with all neighbors. If we can't go further
    # then we decrease the indentation threshold and expand via indentation
    # i.e. `expand_indent`
    #
    # Handles two general cases.
    #
    # ## Case #1: Check code inside of methods/classes/etc.
    #
    # It's important to note, that not everything in a given indentation level can be parsed
    # as valid code even if it's part of valid code. For example:
    #
    #   1 hash = {
    #   2   name: "richard",
    #   3   dog: "cinco",
    #   4 }
    #
    # In this case lines 2 and 3 will be neighbors, but they're invalid until `expand_indent`
    # is called on them.
    #
    # When we are adding code within a method or class (at the same indentation level),
    # use the empty lines to denote the programmer intended logical chunks.
    # Stop and check each one. For example:
    #
    #   1 def dog
    #   2   print "dog"
    #   3
    #   4   hash = {
    #   5 end
    #
    # If we did not stop parsing at empty newlines then the block might mistakenly grab all
    # the contents (lines 2, 3, and 4) and report them as being problems, instead of only
    # line 4.
    #
    # ## Case #2: Expand/grab other logical blocks
    #
    # Once the search algorithm has converted all lines into blocks at a given indentation
    # it will then `expand_indent`. Once the blocks that generates are expanded as neighbors
    # we then begin seeing neighbors being other logical blocks i.e. a block's neighbors
    # may be another method or class (something with keywords/ends).
    #
    # For example:
    #
    #   1 def bark
    #   2
    #   3 end
    #   4
    #   5 def sit
    #   6 end
    #
    # In this case if lines 4, 5, and 6 are in a block when it tries to expand neighbors
    # it will expand up. If it stops after line 2 or 3 it may cause problems since there's a
    # valid kw/end pair, but the block will be checked without it.
    #
    # We try to resolve this edge case with `lookahead_balance_one_line` below.
    def expand_neighbors(block)
      now = AroundBlockScan.new(code_lines: @code_lines, block: block)

      # Initial scan
      now
        .force_add_hidden
        .stop_after_kw
        .scan_neighbors_not_empty

      # Slurp up empties
      now
        .scan_while { |line| line.empty? }

      # If next line is kw and it will balance us, take it
      expanded_lines = now
        .lookahead_balance_one_line
        .lines

      # Don't allocate a block if it won't be used
      #
      # If nothing was taken, return nil to indicate that status
      # used in `def call` to determine if
      # we need to expand up/out (`expand_indent`)
      if block.lines == expanded_lines
        nil
      else
        CodeBlock.new(lines: expanded_lines)
      end
    end

    # Manageable rspec errors
    def inspect
      "#<SyntaxSuggest::CodeBlock:0x0000123843lol >"
    end
  end
end
