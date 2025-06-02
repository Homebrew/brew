# frozen_string_literal: true

module SyntaxSuggest
  # The main function of the frontier is to hold the edges of our search and to
  # evaluate when we can stop searching.

  # There are three main phases in the algorithm:
  #
  # 1. Sanitize/format input source
  # 2. Search for invalid blocks
  # 3. Format invalid blocks into something meaninful
  #
  # The Code frontier is a critical part of the second step
  #
  # ## Knowing where we've been
  #
  # Once a code block is generated it is added onto the frontier. Then it will be
  # sorted by indentation and frontier can be filtered. Large blocks that fully enclose a
  # smaller block will cause the smaller block to be evicted.
  #
  #   CodeFrontier#<<(block) # Adds block to frontier
  #   CodeFrontier#pop # Removes block from frontier
  #
  # ## Knowing where we can go
  #
  # Internally the frontier keeps track of "unvisited" lines which are exposed via `next_indent_line`
  # when called, this method returns, a line of code with the highest indentation.
  #
  # The returned line of code can be used to build a CodeBlock and then that code block
  # is added back to the frontier. Then, the lines are removed from the
  # "unvisited" so we don't double-create the same block.
  #
  #   CodeFrontier#next_indent_line # Shows next line
  #   CodeFrontier#register_indent_block(block) # Removes lines from unvisited
  #
  # ## Knowing when to stop
  #
  # The frontier knows how to check the entire document for a syntax error. When blocks
  # are added onto the frontier, they're removed from the document. When all code containing
  # syntax errors has been added to the frontier, the document will be parsable without a
  # syntax error and the search can stop.
  #
  #   CodeFrontier#holds_all_syntax_errors? # Returns true when frontier holds all syntax errors
  #
  # ## Filtering false positives
  #
  # Once the search is completed, the frontier may have multiple blocks that do not contain
  # the syntax error. To limit the result to the smallest subset of "invalid blocks" call:
  #
  #   CodeFrontier#detect_invalid_blocks
  #
  class CodeFrontier
    def initialize(code_lines:, unvisited: UnvisitedLines.new(code_lines: code_lines))
      @code_lines = code_lines
      @unvisited = unvisited
      @queue = PriorityEngulfQueue.new

      @check_next = true
    end

    def count
      @queue.length
    end

    # Performance optimization
    #
    # Parsing with ripper is expensive
    # If we know we don't have any blocks with invalid
    # syntax, then we know we cannot have found
    # the incorrect syntax yet.
    #
    # When an invalid block is added onto the frontier
    # check document state
    private def can_skip_check?
      check_next = @check_next
      @check_next = false

      if check_next
        false
      else
        true
      end
    end

    # Returns true if the document is valid with all lines
    # removed. By default it checks all blocks in present in
    # the frontier array, but can be used for arbitrary arrays
    # of codeblocks as well
    def holds_all_syntax_errors?(block_array = @queue, can_cache: true)
      return false if can_cache && can_skip_check?

      without_lines = block_array.to_a.flat_map do |block|
        block.lines
      end

      SyntaxSuggest.valid_without?(
        without_lines: without_lines,
        code_lines: @code_lines
      )
    end

    # Returns a code block with the largest indentation possible
    def pop
      @queue.pop
    end

    def next_indent_line
      @unvisited.peek
    end

    def expand?
      return false if @queue.empty?
      return true if @unvisited.empty?

      frontier_indent = @queue.peek.current_indent
      unvisited_indent = next_indent_line.indent

      if ENV["SYNTAX_SUGGEST_DEBUG"]
        puts "```"
        puts @queue.peek
        puts "```"
        puts "  @frontier indent:  #{frontier_indent}"
        puts "  @unvisited indent: #{unvisited_indent}"
      end

      # Expand all blocks before moving to unvisited lines
      frontier_indent >= unvisited_indent
    end

    # Keeps track of what lines have been added to blocks and which are not yet
    # visited.
    def register_indent_block(block)
      @unvisited.visit_block(block)
      self
    end

    # When one element fully encapsulates another we remove the smaller
    # block from the frontier. This prevents double expansions and all-around
    # weird behavior. However this guarantee is quite expensive to maintain
    def register_engulf_block(block)
    end

    # Add a block to the frontier
    #
    # This method ensures the frontier always remains sorted (in indentation order)
    # and that each code block's lines are removed from the indentation hash so we
    # don't re-evaluate the same line multiple times.
    def <<(block)
      @unvisited.visit_block(block)

      @queue.push(block)

      @check_next = true if block.invalid?

      self
    end

    # Example:
    #
    #   combination([:a, :b, :c, :d])
    #   # => [[:a], [:b], [:c], [:d], [:a, :b], [:a, :c], [:a, :d], [:b, :c], [:b, :d], [:c, :d], [:a, :b, :c], [:a, :b, :d], [:a, :c, :d], [:b, :c, :d], [:a, :b, :c, :d]]
    def self.combination(array)
      guesses = []
      1.upto(array.length).each do |size|
        guesses.concat(array.combination(size).to_a)
      end
      guesses
    end

    # Given that we know our syntax error exists somewhere in our frontier, we want to find
    # the smallest possible set of blocks that contain all the syntax errors
    def detect_invalid_blocks
      self.class.combination(@queue.to_a.select(&:invalid?)).detect do |block_array|
        holds_all_syntax_errors?(block_array, can_cache: false)
      end || []
    end
  end
end
